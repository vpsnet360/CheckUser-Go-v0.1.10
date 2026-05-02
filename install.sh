#!/bin/bash

get_arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        * ) echo 'unsupported' ;;
    esac
}

install_checkuser() {
    echo -e "\n\e[1;36m⚙️  Configuración de CheckUser v0.1.10\e[0m"

    local port="2052"

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
ExecStart=/usr/local/bin/checkuser -start -port $port
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

    local final_url="http://$addr:$port"

    # Verificar
    if systemctl is-active --quiet checkuser; then
        echo -e "\n\e[1;32m====================================\e[0m"
        echo -e "\e[1;32m✅ CheckUser v0.1.10 INSTALADO!\e[0m"
        echo -e "\e[1;32m🌐 URL: \e[1;33m$final_url\e[0m"
        echo -e "\e[1;32m====================================\e[0m"

        # Probar conexión
        if curl -s --max-time 3 "$final_url" &>/dev/null; then
            echo -e "\e[1;32m✅ Servicio funcionando correctamente!\e[0m"
        else
            echo -e "\e[1;33m⚠️  Verifica el firewall: sudo ufw allow $port/tcp\e[0m"
        fi
    else
        echo -e "\e[1;31m❌ Error al iniciar el servicio\e[0m"
        echo -e "\e[1;33mLogs: sudo journalctl -u checkuser -n 20\e[0m"
        
        # Mostrar el código de salida para debugging
        echo -e "\n\e[1;33mCódigo de salida del proceso:\e[0m"
        sudo journalctl -u checkuser --no-pager | grep "code=exited" | tail -1
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
    while true; do
        clear
        echo '---------------------------------'
        echo -ne "     \e[1;33mCHECKUSER v0.1.10\e[0m"
        if [[ -x /usr/local/bin/checkuser ]]; then
            echo -e " \e[1;32m[INSTALADO]\e[0m"
        else
            echo -e " \e[1;31m[NO INSTALADO]\e[0m"
        fi
        echo '---------------------------------'
        echo -e "\e[1;32m[01] - INSTALAR CHECKUSER\e[0m"
        echo -e "\e[1;32m[02] - REINSTALAR CHECKUSER\e[0m"
        echo -e "\e[1;32m[03] - DESINSTALAR CHECKUSER\e[0m"
        echo -e "\e[1;32m[00] - SALIR\e[0m"
        echo '---------------------------------'
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
