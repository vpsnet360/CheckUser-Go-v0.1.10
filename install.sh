#!/bin/bash

get_arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        * ) echo 'unsupported' ;;
    esac
}

install_certbot() {
    echo -e "\n\e[1;33m📦 Instalando Certbot...\e[0m"
    
    if command -v apt &>/dev/null; then
        sudo apt update -y &>/dev/null
        sudo apt install -y certbot &>/dev/null
    elif command -v yum &>/dev/null; then
        sudo yum install -y certbot &>/dev/null
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y certbot &>/dev/null
    else
        echo -e "\e[1;31m❌ No se pudo instalar certbot. Instala manualmente\e[0m"
        return 1
    fi
    
    echo -e "\e[1;32m✅ Certbot instalado\e[0m"
    return 0
}

generate_letsencrypt_cert() {
    local domain=$1
    local email=$2
    local cert_dir="/etc/checkuser/ssl"
    
    echo -e "\n🔐 Generando certificado SSL con Let's Encrypt para $domain..."
    echo -e "\e[1;33m⚠️  REQUISITOS IMPORTANTES:\e[0m"
    echo -e "\e[1;33m  1. El dominio $domain debe apuntar a este servidor (registro A)\e[0m"
    echo -e "\e[1;33m  2. El puerto 80 debe estar libre (detén nginx/apache si es necesario)\e[0m"
    echo -e "\e[1;33m  3. El servidor debe ser accesible desde Internet\e[0m"
    echo -ne "\e[1;33m¿Continuar? [s/N]: \e[0m"
    read confirm
    [[ "$confirm" != "s" && "$confirm" != "S" ]] && return 1
    
    # Instalar certbot si no existe
    if ! command -v certbot &>/dev/null; then
        install_certbot || return 1
    fi
    
    mkdir -p "$cert_dir"
    
    # Detener servicios que puedan ocupar el puerto 80 temporalmente
    echo -e "\e[1;33m🔄 Deteniendo servicios web temporalmente...\e[0m"
    sudo systemctl stop nginx &>/dev/null
    sudo systemctl stop apache2 &>/dev/null
    sudo systemctl stop httpd &>/dev/null
    
    # Generar certificado con certbot standalone
    echo -e "\e[1;33m🔐 Generando certificado (puede tomar unos segundos)...\e[0m"
    sudo certbot certonly --standalone \
        --non-interactive \
        --agree-tos \
        --email "$email" \
        -d "$domain" 2>/tmp/certbot_error.log
    
    if [[ $? -eq 0 ]]; then
        # Copiar certificados al directorio de checkuser
        sudo cp /etc/letsencrypt/live/$domain/fullchain.pem "$cert_dir/certificate.crt"
        sudo cp /etc/letsencrypt/live/$domain/privkey.pem "$cert_dir/private.key"
        sudo chmod 644 "$cert_dir/certificate.crt"
        sudo chmod 600 "$cert_dir/private.key"
        
        echo -e "\e[1;32m✅ Certificado SSL de Let's Encrypt generado exitosamente!\e[0m"
        echo -e "   📁 Certificado: $cert_dir/certificate.crt"
        echo -e "   🔑 Clave privada: $cert_dir/private.key"
        echo -e "   ⏰ Válido por 90 días"
        
        # Configurar renovación automática
        echo -e "\e[1;33m🔄 Configurando renovación automática...\e[0m"
        
        # Crear script de renovación
        cat << 'EOF' | sudo tee /etc/checkuser/renew-cert.sh > /dev/null
#!/bin/bash
certbot renew --quiet
cp /etc/letsencrypt/live/$1/fullchain.pem /etc/checkuser/ssl/certificate.crt
cp /etc/letsencrypt/live/$1/privkey.pem /etc/checkuser/ssl/private.key
chmod 644 /etc/checkuser/ssl/certificate.crt
chmod 600 /etc/checkuser/ssl/private.key
systemctl restart checkuser
EOF
        
        sudo sed -i "s/\$1/$domain/g" /etc/checkuser/renew-cert.sh
        sudo chmod +x /etc/checkuser/renew-cert.sh
        
        # Agregar al crontab para renovación automática
        (sudo crontab -l 2>/dev/null; echo "0 0 1 * * /etc/checkuser/renew-cert.sh") | sudo crontab - 2>/dev/null
        
        echo -e "\e[1;32m✅ Renovación automática configurada (cada mes)\e[0m"
        
        return 0
    else
        echo -e "\e[1;31m❌ Error al generar certificado Let's Encrypt\e[0m"
        echo -e "\e[1;33mError: $(cat /tmp/certbot_error.log)\e[0m"
        return 1
    fi
}

install_checkuser() {
    echo -e "\n\e[1;36m⚙️  Configuración de CheckUser v0.1.10\e[0m"
    echo -e "\e[1;33m════════════════════════════════════\e[0m"
    echo -e "\e[1;32m[1] - Sin SSL (HTTP - Puerto 2053)\e[0m"
    echo -e "\e[1;32m[2] - Con SSL Let's Encrypt (HTTPS - Puerto 2053) 🔒\e[0m"
    echo -e "\e[1;33m════════════════════════════════════\e[0m"
    echo -ne "\e[1;33mElige una opción [1-2]: \e[0m"
    read ssl_option

    local port="2053"
    local ssl_params=""

    # Obtener IP pública
    local addr
    addr=$(curl -s --max-time 5 https://ipv4.icanhazip.com)
    if [[ -z "$addr" ]]; then
        echo -e "\e[1;31m❌ No se pudo obtener la IP pública. Verifica tu conexión.\e[0m"
        return 1
    fi

    # Obtener versión
    local repo="vpsnet360/CheckUser-Go-v0.1.10"
    local latest_release
    latest_release=$(curl -s https://api.github.com/repos/$repo/releases/latest | grep '"tag_name"' | head -1 | cut -d'"' -f4)

    if [[ -z "$latest_release" ]]; then
        echo -e "\e[1;31m❌ No se pudo obtener la última versión. Usando versión por defecto\e[0m"
        latest_release="v0.1.10"
    fi

    local arch
    arch=$(get_arch)
    if [ "$arch" = "unsupported" ]; then
        echo -e "\e[1;31mArquitectura de CPU no soportada!\e[0m"
        exit 1
    fi

    echo -e "\e[1;33m📥 Descargando CheckUser versión: $latest_release para $arch...\e[0m"
    local name="checkuser-linux-$arch"
    local download_url="https://github.com/$repo/releases/download/$latest_release/$name"

    wget -q --show-progress "$download_url" -O /usr/local/bin/checkuser

    if [[ $? -ne 0 ]]; then
        echo -e "\e[1;31m❌ Error al descargar. Intentando URL alternativa...\e[0m"
        download_url="https://github.com/$repo/releases/download/v0.1.10/$name"
        wget -q --show-progress "$download_url" -O /usr/local/bin/checkuser
        if [[ $? -ne 0 ]]; then
            echo -e "\e[1;31m❌ No se pudo descargar el binario. Abortando.\e[0m"
            return 1
        fi
    fi

    chmod +x /usr/local/bin/checkuser

    # CREAR DIRECTORIO DE TRABAJO
    mkdir -p /etc/checkuser
    echo -e "\e[1;32m✅ Directorio /etc/checkuser creado\e[0m"

    case $ssl_option in
        1)
            ssl_params=""
            final_url="http://$addr:$port"
            echo -e "\e[1;33m⚠️  Modo HTTP sin SSL - No recomendado para producción\e[0m"
            ;;
        2)
            echo -ne "\e[1;33m🌐 Ingresa tu dominio (ej: check.midominio.com): \e[0m"
            read custom_domain
            
            if [[ -z "$custom_domain" ]]; then
                echo -e "\e[1;31m❌ Debes ingresar un dominio para SSL\e[0m"
                echo -e "\e[1;33m⚠️  Instalando sin SSL...\e[0m"
                ssl_params=""
                final_url="http://$addr:$port"
            else
                echo -ne "\e[1;33m📧 Ingresa tu email para Let's Encrypt: \e[0m"
                read email
                [[ -z "$email" ]] && email="admin@$custom_domain"
                
                if generate_letsencrypt_cert "$custom_domain" "$email"; then
                    ssl_params="-ssl"
                    final_url="https://$custom_domain:$port"
                    echo -e "\e[1;32m✅ SSL Let's Encrypt configurado - Certificado VÁLIDO!\e[0m"
                else
                    echo -e "\e[1;31m❌ No se pudo generar el certificado SSL\e[0m"
                    echo -e "\e[1;33m⚠️  Instalando sin SSL...\e[0m"
                    ssl_params=""
                    final_url="http://$addr:$port"
                fi
            fi
            ;;
        *)
            echo -e "\e[1;31m❌ Opción inválida\e[0m"
            return 1
            ;;
    esac

    # ABRIR PUERTOS EN EL FIREWALL
    if command -v ufw &>/dev/null; then
        echo -e "\e[1;33m🔓 Configurando firewall...\e[0m"
        sudo ufw allow $port/tcp &>/dev/null
        [[ -n "$ssl_params" ]] && sudo ufw allow 80/tcp &>/dev/null
        sudo ufw reload &>/dev/null
        echo -e "\e[1;32m✅ Puerto $port/tcp abierto en UFW\e[0m"
        [[ -n "$ssl_params" ]] && echo -e "\e[1;32m✅ Puerto 80/tcp abierto en UFW (para renovación)\e[0m"
    elif command -v firewall-cmd &>/dev/null; then
        echo -e "\e[1;33m🔓 Configurando firewall...\e[0m"
        sudo firewall-cmd --permanent --add-port=$port/tcp &>/dev/null
        [[ -n "$ssl_params" ]] && sudo firewall-cmd --permanent --add-port=80/tcp &>/dev/null
        sudo firewall-cmd --reload &>/dev/null
        echo -e "\e[1;32m✅ Puerto $port/tcp abierto en firewalld\e[0m"
    fi

    # Detener servicio existente
    sudo systemctl stop checkuser &>/dev/null
    sudo systemctl disable checkuser &>/dev/null
    sudo rm -f /etc/systemd/system/checkuser.service
    sudo systemctl daemon-reload

    # Crear servicio systemd
    cat << EOF | sudo tee /etc/systemd/system/checkuser.service > /dev/null
[Unit]
Description=CheckUser Service v0.1.10
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/checkuser -start -port $port $ssl_params
Restart=always
RestartSec=5
WorkingDirectory=/etc/checkuser

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl start checkuser
    sudo systemctl enable checkuser

    sleep 2

    # Verificar
    if systemctl is-active --quiet checkuser; then
        echo -e "\n\e[1;32m════════════════════════════════════\e[0m"
        echo -e "\e[1;32m✅ CheckUser v0.1.10 INSTALADO!\e[0m"
        echo -e "\e[1;32m🌐 URL: \e[1;33m$final_url\e[0m"
        echo -e "\e[1;32m🔓 Puerto: \e[1;33m$port/tcp\e[0m"
        [[ -n "$ssl_params" ]] && echo -e "\e[1;32m🔒 SSL: \e[1;33mLet's Encrypt (Válido)\e[0m" || echo -e "\e[1;31m⚠️  SSL: \e[1;33mDesactivado\e[0m"
        echo -e "\e[1;32m════════════════════════════════════\e[0m"

        # Probar conexión
        if curl -s --max-time 3 "$final_url" &>/dev/null; then
            echo -e "\e[1;32m✅ Servicio funcionando correctamente!\e[0m"
        else
            echo -e "\e[1;33m⚠️  Verifica la conectividad al puerto $port\e[0m"
        fi
    else
        echo -e "\e[1;31m❌ Error al iniciar el servicio\e[0m"
        echo -e "\e[1;33mLogs: sudo journalctl -u checkuser -n 20\e[0m"
        sudo journalctl -u checkuser --no-pager -n 5
    fi

    echo -e "\nPresiona Enter para continuar..."
    read
}

reinstall_checkuser() {
    echo -e "\e[1;33m🔄 Reinstalando CheckUser...\e[0m"
    sudo systemctl stop checkuser &>/dev/null
    sudo systemctl disable checkuser &>/dev/null
    sudo rm -f /usr/local/bin/checkuser
    sudo rm -f /etc/systemd/system/checkuser.service
    sudo rm -rf /etc/checkuser
    sudo systemctl daemon-reload
    install_checkuser
}

uninstall_checkuser() {
    echo -e "\e[1;33m🗑️  Desinstalando CheckUser...\e[0m"
    sudo systemctl stop checkuser &>/dev/null
    sudo systemctl disable checkuser &>/dev/null
    sudo rm -f /usr/local/bin/checkuser
    sudo rm -f /etc/systemd/system/checkuser.service
    sudo rm -rf /etc/checkuser
    sudo systemctl daemon-reload
    # Eliminar certificados de Let's Encrypt si existen
    if [[ -n "$domain" ]]; then
        sudo certbot delete --cert-name "$domain" &>/dev/null
    fi
    echo -e "\e[1;32m✅ CheckUser desinstalado correctamente\e[0m"
    echo -e "\nPresiona Enter para continuar..."
    read
}

main() {
    while true; do
        clear
        echo '════════════════════════════════════'
        echo -ne "     \e[1;33mCHECKUSER v0.1.10\e[0m"
        if [[ -x /usr/local/bin/checkuser ]]; then
            echo -e " \e[1;32m[INSTALADO]\e[0m"
        else
            echo -e " \e[1;31m[NO INSTALADO]\e[0m"
        fi
        echo '════════════════════════════════════'
        echo -e "\e[1;32m[01] - INSTALAR CHECKUSER\e[0m"
        echo -e "\e[1;32m[02] - REINSTALAR CHECKUSER\e[0m"
        echo -e "\e[1;32m[03] - DESINSTALAR CHECKUSER\e[0m"
        echo -e "\e[1;32m[00] - SALIR\e[0m"
        echo '════════════════════════════════════'
        echo -ne "\e[1;32mElige una opción: \e[0m"
        read option

        case $option in
            1|01) install_checkuser ;;
            2|02) reinstall_checkuser ;;
            3|03) uninstall_checkuser ;;
            0|00) echo "Saliendo..."; exit 0 ;;
            *) echo -e "\e[1;31mOpción inválida\e[0m"; sleep 2 ;;
        esac
    done
}

main
