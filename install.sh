#!/bin/bash

get_arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        * ) echo 'unsupported' ;;
    esac
}

generate_self_signed_cert() {
    local domain=$1
    local cert_dir="/etc/checkuser/ssl"
    
    echo -e "\n🔐 Generando certificado SSL autofirmado para $domain..."
    
    mkdir -p "$cert_dir"
    
    openssl req -x509 -newkey rsa:4096 -keyout "$cert_dir/private.key" -out "$cert_dir/certificate.crt" -days 365 -nodes -subj "/CN=$domain"
    
    if [[ -f "$cert_dir/private.key" && -f "$cert_dir/certificate.crt" ]]; then
        echo -e "\e[1;32m✅ Certificado SSL generado exitosamente!\e[0m"
        return 0
    else
        echo -e "\e[1;31m❌ Fallo al generar certificado SSL!\e[0m"
        return 1
    fi
}

install_checkuser() {
    echo -e "\n\e[1;36m⚙️  Configuración de CheckUser v1.1.10\e[0m"
    echo -e "\e[1;32m[1] - Sin SSL (HTTP - Puerto 2052)\e[0m"
    echo -e "\e[1;32m[2] - SSL con certificado autofirmado (HTTPS - Puerto 2053)\e[0m"
    echo -ne "\e[1;33mElige una opción: \e[0m"
    read ssl_option

    local port=""
    local ssl_params=""
    local addr=$(curl -s https://ipv4.icanhazip.com)
    
    # OBTENER LA VERSIÓN CORRECTA
    local repo="vpsnet360/CheckUser-Go-v0.1.10"
    local latest_release=$(curl -s https://api.github.com/repos/$repo/releases/latest | grep '"tag_name"' | head -1 | cut -d'"' -f4)
    
    if [[ -z "$latest_release" ]]; then
        echo -e "\e[1;31m❌ No se pudo obtener la última versión. Usando versión por defecto\e[0m"
        latest_release="v1.1.10"
    fi
    
    local arch=$(get_arch)
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
        download_url="https://github.com/$repo/releases/download/v1.1.10/$name"
        wget -q --show-progress "$download_url" -O /usr/local/bin/checkuser
    fi
    
    chmod +x /usr/local/bin/checkuser

    case $ssl_option in
        1)
            port="2052"
            ssl_params=""
            final_url="http://$addr:$port"
            echo -e "\e[1;33m⚠️  Instalando sin SSL\e[0m"
            ;;
        2)
            port="2053"
            echo -ne "\e[1;33mIngresa tu dominio o IP para el certificado: \e[0m"
            read custom_domain
            [[ -z "$custom_domain" ]] && custom_domain="$addr"
            
            if generate_self_signed_cert "$custom_domain"; then
                ssl_params="--ssl --cert /etc/checkuser/ssl/certificate.crt --key /etc/checkuser/ssl/private.key"
                final_url="https://$custom_domain:$port"
                echo -e "\e[1;32m✅ SSL configurado correctamente\e[0m"
            else
                echo -e "\e[1;31m❌ Error SSL, instalando sin SSL...\e[0m"
                port="2052"
                ssl_params=""
                final_url="http://$addr:2052"
            fi
            ;;
        *)
            echo -e "\e[1;31mOpción inválida\e[0m"
            return 1
            ;;
    esac

    # Detener servicio existente
    sudo systemctl stop checkuser &>/dev/null
    sudo systemctl disable checkuser &>/dev/null
    sudo rm -f /etc/systemd/system/checkuser.service
    sudo systemctl daemon-reload

    # Crear servicio systemd
    cat << EOF | sudo tee /etc/systemd/system/checkuser.service > /dev/null
[Unit]
Description=CheckUser Service v1.1.10
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/checkuser --start --port $port $ssl_params
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
        echo -e "\n\e[1;32m====================================\e[0m"
        echo -e "\e[1;32m✅ CheckUser v1.1.10 INSTALADO!\e[0m"
        echo -e "\e[1;32m🌐 URL: \e[1;33m$final_url\e[0m"
        echo -e "\e[1;32m====================================\e[0m"
        
        # Probar conexión
        if curl -s --max-time 3 --insecure "$final_url" &>/dev/null; then
            echo -e "\e[1;32m✅ Servicio funcionando correctamente!\e[0m"
        else
            echo -e "\e[1;33m⚠️  Verifica el firewall: sudo ufw allow $port/tcp\e[0m"
        fi
    else
        echo -e "\e[1;31m❌ Error al iniciar el servicio\e[0m"
        echo -e "\e[1;33mLogs: sudo journalctl -u checkuser -n 20\e[0m"
    fi
    
    echo -e "\nPresiona Enter para continuar..."
    read
}

reinstall_checkuser() {
    echo "Reinstalando CheckUser..."
    sudo systemctl stop checkuser &>/dev/null
    sudo systemctl disable checkuser &>/dev/null
    sudo rm -f /usr/local/bin/checkuser
    sudo rm -f /etc/systemd/system/checkuser.service
    sudo rm -rf /etc/checkuser
    sudo systemctl daemon-reload
    install_checkuser
}

uninstall_checkuser() {
    echo "Desinstalando CheckUser..."
    sudo systemctl stop checkuser &>/dev/null
    sudo systemctl disable checkuser &>/dev/null
    sudo rm -f /usr/local/bin/checkuser
    sudo rm -f /etc/systemd/system/checkuser.service
    sudo rm -rf /etc/checkuser
    sudo systemctl daemon-reload
    echo -e "\e[1;32m✅ CheckUser desinstalado\e[0m"
    echo -e "\nPresiona Enter para continuar..."
    read
}

main() {
    clear
    echo '---------------------------------'
    echo -ne '     \e[1;33mCHECKUSER v1.1.10\e[0m'
    if [[ -x /usr/local/bin/checkuser ]]; then
        echo -e ' \e[1;32m[INSTALADO]\e[0m'
    else
        echo -e ' \e[1;31m[NO INSTALADO]\e[0m'
    fi
    echo '---------------------------------'
    echo -e '\e[1;32m[01] - INSTALAR CHECKUSER\e[0m'
    echo -e '\e[1;32m[02] - REINSTALAR CHECKUSER\e[0m'
    echo -e '\e[1;32m[03] - DESINSTALAR CHECKUSER\e[0m'
    echo -e '\e[1;32m[00] - SALIR\e[0m'
    echo '---------------------------------'
    echo -ne '\e[1;32mElige una opción: \e[0m'
    read option

    case $option in
        1) install_checkuser; main ;;
        2) reinstall_checkuser; main ;;
        3) uninstall_checkuser; main ;;
        0) echo "Saliendo..." ; exit 0 ;;
        *) echo -e "\e[1;31mOpción inválida\e[0m"; sleep 2; main ;;
    esac
}

main