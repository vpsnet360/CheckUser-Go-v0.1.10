#!/bin/bash

get_arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        * ) echo 'unsupported' ;;
    esac
}

install_certificate() {
    local domain=$1
    
    echo -e "\e[1;33mInstalando certificado SSL para $domain...\e[0m"
    
    # Verificar si certbot está instalado
    if ! command -v certbot &> /dev/null; then
        echo -e "\e[1;33mInstalando certbot...\e[0m"
        if command -v apt &> /dev/null; then
            sudo apt update -y &>/dev/null
            sudo apt install certbot -y &>/dev/null
        elif command -v yum &> /dev/null; then
            sudo yum install certbot -y &>/dev/null
        else
            echo -e "\e[1;31mNo se pudo instalar certbot. Sistema no soportado.\e[0m"
            return 1
        fi
    fi
    
    # Detener temporalmente el servicio checkuser para liberar el puerto 80
    echo -e "\e[1;33mDeteniendo checkuser temporalmente para validación...\e[0m"
    sudo systemctl stop checkuser &>/dev/null
    
    # Obtener certificado standalone (usa puerto 80 para validación)
    echo -e "\e[1;33mObteniendo certificado SSL...\e[0m"
    if sudo certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email -d "$domain"; then
        echo -e "\e[1;32m✅ Certificado SSL obtenido exitosamente!\e[0m"
        
        # La ruta donde se guardan los certificados
        local cert_path="/etc/letsencrypt/live/$domain"
        echo -e "\e[1;32mCertificado guardado en: $cert_path\e[0m"
        echo -e "\e[1;32m  - Certificado: $cert_path/fullchain.pem\e[0m"
        echo -e "\e[1;32m  - Clave privada: $cert_path/privkey.pem\e[0m"
        
        # Configurar renovación automática
        echo -e "\e[1;33mConfigurando renovación automática...\e[0m"
        # Agregar hook para detener checkuser antes de renovar
        sudo mkdir -p /etc/letsencrypt/renewal-hooks/pre
        sudo mkdir -p /etc/letsencrypt/renewal-hooks/post
        
        echo '#!/bin/bash
systemctl stop checkuser' | sudo tee /etc/letsencrypt/renewal-hooks/pre/checkuser-stop.sh > /dev/null
        sudo chmod +x /etc/letsencrypt/renewal-hooks/pre/checkuser-stop.sh
        
        echo '#!/bin/bash
systemctl start checkuser' | sudo tee /etc/letsencrypt/renewal-hooks/post/checkuser-start.sh > /dev/null
        sudo chmod +x /etc/letsencrypt/renewal-hooks/post/checkuser-start.sh
        
        # Probar renovación automática
        echo -e "\e[1;33mProbando renovación automática...\e[0m"
        sudo certbot renew --dry-run &>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "\e[1;32m✅ Renovación automática configurada correctamente.\e[0m"
        else
            echo -e "\e[1;31m⚠️  Hubo un problema con la renovación automática.\e[0m"
        fi
        
        return 0
    else
        echo -e "\e[1;31m❌ Error al obtener el certificado SSL.\e[0m"
        echo -e "\e[1;33mVerifica que:\e[0m"
        echo -e "\e[1;33m  1. El dominio $domain apunte a este servidor\e[0m"
        echo -e "\e[1;33m  2. El puerto 80 esté abierto en el firewall\e[0m"
        return 1
    fi
}

install_checkuser() {
    local latest_release=$(curl -s https://api.github.com/repos/DTunnel0/CheckUser-Go/releases/latest | grep "tag_name" | cut -d'"' -f4)
    local arch=$(get_arch)

    if [ "$arch" = "unsupported" ]; then
        echo -e "\e[1;31mArquitetura de CPU não suportada!\e[0m"
        exit 1
    fi

    local name="checkuser-linux-$arch"
    echo "Baixando $name..."
    wget -q "https://github.com/DTunnel0/CheckUser-Go/releases/download/$latest_release/$name" -O /usr/local/bin/checkuser
    chmod +x /usr/local/bin/checkuser

    local addr=$(curl -s https://ipv4.icanhazip.com)
    
    # Solicitar dominio
    echo -ne "\e[1;33mDigite seu domínio (ej: checkuser.midominio.com) o deixe em branco para usar IP direto: \e[0m"
    read user_domain
    
    if [[ -z $user_domain ]]; then
        local url=""
        local port="2052"
        local sslEnabled=""
    else
        # Instalar certificado SSL
        if install_certificate "$user_domain"; then
            local url="$user_domain"
            local port="2053"
            # Usar los certificados obtenidos
            local cert_path="/etc/letsencrypt/live/$user_domain"
            local sslEnabled="--ssl --cert-file $cert_path/fullchain.pem --key-file $cert_path/privkey.pem"
        else
            echo -e "\e[1;33mContinuando sin SSL...\e[0m"
            local url=""
            local port="2052"
            local sslEnabled=""
        fi
    fi

    if systemctl status checkuser &>/dev/null 2>&1; then
        echo "Parando o serviço checkuser existente..."
        sudo systemctl stop checkuser
        sudo systemctl disable checkuser
        sudo rm /etc/systemd/system/checkuser.service
        sudo systemctl daemon-reload
        echo "Serviço checkuser existente foi parado e removido."
    fi

    # Si hay certificado, re-iniciar checkuser que fue detenido para la validación
    if [[ ! -z $sslEnabled ]]; then
        echo -e "\e[1;33mReiniciando checkuser con SSL...\e[0m"
    fi

    cat << EOF | sudo tee /etc/systemd/system/checkuser.service > /dev/null
[Unit]
Description=CheckUser Service
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/checkuser --start --port $port $sslEnabled
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload &>/dev/null
    sudo systemctl start checkuser &>/dev/null
    sudo systemctl enable checkuser &>/dev/null

    # Verificar conexión
    sleep 2
    if [[ -z $url ]]; then
        echo -e "\e[1;32m====================================\e[0m"
        echo -e "\e[1;32mURL: \e[1;33mhttp://$addr:$port\e[0m"
        echo -e "\e[1;32m====================================\e[0m"
        
        echo -e "\e[1;33mProbando servicio...\e[0m"
        if curl -s http://$addr:$port > /dev/null 2>&1; then
            echo -e "\e[1;32m✅ Servicio funcionando correctamente!\e[0m"
        else
            echo -e "\e[1;31m⚠️  No se pudo verificar. Verifica: sudo journalctl -u checkuser\e[0m"
        fi
    else 
        echo -e "\e[1;32m====================================\e[0m"
        echo -e "\e[1;32mURL: \e[1;33mhttps://$url:$port\e[0m"
        echo -e "\e[1;32m====================================\e[0m"
        
        echo -e "\e[1;33mVerificando SSL...\e[0m"
        if curl -sk https://$url:$port > /dev/null 2>&1; then
            echo -e "\e[1;32m✅ Servicio HTTPS funcionando con certificado SSL válido!\e[0m"
            echo -e "\e[1;33mPara verificar el certificado:\e[0m"
            echo -e "\e[1;33m  curl -vI https://$url:$port\e[0m"
        else
            echo -e "\e[1;31m⚠️  No se pudo verificar HTTPS. Revisa:\e[0m"
            echo -e "\e[1;33m  sudo journalctl -u checkuser\e[0m"
        fi
    fi

    echo -e "\e[1;32mO serviço CheckUser foi instalado e iniciado.\e[0m"
    read
}

reinstall_checkuser() {
    echo "Parando e removendo o serviço checkuser..."
    sudo systemctl stop checkuser &>/dev/null
    sudo systemctl disable checkuser &>/dev/null
    sudo rm /usr/local/bin/checkuser
    sudo rm /etc/systemd/system/checkuser.service
    sudo systemctl daemon-reload &>/dev/null
    echo "Serviço checkuser removido."

    install_checkuser
}

uninstall_checkuser() {
    sudo systemctl stop checkuser &>/dev/null
    sudo systemctl disable checkuser &>/dev/null
    sudo rm /usr/local/bin/checkuser
    sudo rm /etc/systemd/system/checkuser.service
    sudo systemctl daemon-reload &>/dev/null
    echo "Serviço checkuser removido."
    read
}

main() {
    clear

    echo '---------------------------------'
    echo -ne '     \e[1;33mCHECKUSER\e[0m'
    if [[ -e /usr/local/bin/checkuser ]]; then
        echo -e ' \e[1;32mv'$(/usr/local/bin/checkuser --version | cut -d' ' -f2)'\e[0m'
    else
        echo -e ' \e[1;31m[DESINSTALADO]\e[0m'
    fi
    echo '---------------------------------'

    echo -e '\e[1;32m[01] - \e[1;31mINSTALAR CHECKUSER\e[0m'
    echo -e '\e[1;32m[02] - \e[1;31mREINSTALAR CHECKUSER\e[0m'
    echo -e '\e[1;32m[03] - \e[1;31mDESINSTALAR CHECKUSER\e[0m'
    echo -e '\e[1;32m[00] - \e[1;31mSAIR\e[0m'
    echo '---------------------------------'
    echo -ne '\e[1;32mEscolha uma opção: \e[0m'; 
    read option

    case $option in
        1) install_checkuser; main ;;
        2) reinstall_checkuser; main ;;
        3) uninstall_checkuser; main ;;
        0) echo "Saindo.";;
        *) echo -e "\e[1;31mOpção inválida. Tente novamente.\e[0m";read; main ;;
    esac
}

main