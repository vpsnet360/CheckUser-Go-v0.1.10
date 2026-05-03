#!/bin/bash
# ============================================================
#   CHECKUSER SSL INSTALLER - Nginx + Let's Encrypt
#   Busca siempre la última versión automáticamente
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

OK="${GREEN}[✓]${NC}"
ERR="${RED}[✗]${NC}"
INFO="${CYAN}[i]${NC}"
WARN="${YELLOW}[!]${NC}"

get_arch() {
    case "$(uname -m)" in
        x86_64 | x64 | amd64 ) echo 'amd64' ;;
        armv8 | arm64 | aarch64 ) echo 'arm64' ;;
        * ) echo 'unsupported' ;;
    esac
}

get_latest_version() {
    local repo=$1
    local latest_release
    
    echo -e "${INFO} Buscando última versión de CheckUser en $repo..." >&2
    
    local response
    response=$(curl -s "https://api.github.com/repos/$repo/releases/latest")
    
    if echo "$response" | grep -q "Not Found"; then
        echo -e "${WARN} Repositorio $repo no encontrado" >&2
        return 1
    fi
    
    if echo "$response" | grep -q "rate limit exceeded"; then
        echo -e "${ERR} Rate limit de GitHub excedido" >&2
        return 1
    fi
    
    # Extraer SOLO el tag
    latest_release=$(echo "$response" | grep -oP '"tag_name":\s*"\K[^"]+' | head -1)
    
    if [[ -z "$latest_release" ]]; then
        echo -e "${WARN} No se pudo obtener versión de $repo" >&2
        return 1
    fi
    
    echo -e "${OK} Última versión encontrada: ${CYAN}${latest_release}${NC}" >&2
    # Solo devolver el valor limpio
    printf "%s" "$latest_release"
}

install_dependencies() {
    echo -e "${INFO} Instalando dependencias (nginx, certbot, curl)..."
    
    if command -v apt &>/dev/null; then
        sudo apt update -y &>/dev/null
        sudo apt install -y nginx certbot python3-certbot-nginx curl wget dnsutils &>/dev/null
    elif command -v yum &>/dev/null; then
        sudo yum install -y epel-release &>/dev/null
        sudo yum install -y nginx certbot python3-certbot-nginx curl wget bind-utils &>/dev/null
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y nginx certbot python3-certbot-nginx curl wget bind-utils &>/dev/null
    else
        echo -e "${ERR} No se pudo instalar dependencias"
        return 1
    fi
    
    echo -e "${OK} Dependencias instaladas"
    return 0
}

install_checkuser_binary() {
    if [[ -x /usr/local/bin/checkuser ]]; then
        local current_version
        current_version=$(/usr/local/bin/checkuser -version 2>&1 | grep -oP 'v[\d.]+' || echo "desconocida")
        echo -e "${OK} CheckUser ya instalado (versión: ${CYAN}${current_version}${NC})"
        
        echo -ne "${WARN} ¿Buscar actualización? [s/N]: "
        read update_confirm
        [[ "$update_confirm" != "s" && "$update_confirm" != "S" ]] && return 0
    fi

    local repos=(
        "DTunnel0/CheckUser-Go"
    )
    
    local latest_version=""
    local selected_repo=""
    
    for repo in "${repos[@]}"; do
        echo -e "${INFO} Buscando en repositorio: ${CYAN}${repo}${NC}"
        latest_version=$(get_latest_version "$repo")
        
        if [[ -n "$latest_version" && "$latest_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            selected_repo="$repo"
            break
        fi
    done
    
    if [[ -z "$latest_version" ]]; then
        echo -e "${ERR} No se pudo encontrar CheckUser válido"
        return 1
    fi

    local arch
    arch=$(get_arch)
    if [ "$arch" = "unsupported" ]; then
        echo -e "${ERR} Arquitectura no soportada: $(uname -m)"
        return 1
    fi

    echo -e "${INFO} Versión: ${CYAN}${latest_version}${NC} | Arquitectura: ${CYAN}${arch}${NC}"
    
    # URL directa sin consultar assets
    local download_url="https://github.com/$selected_repo/releases/download/$latest_version/checkuser-linux-$arch"
    
    echo -e "${INFO} Descargando: ${CYAN}checkuser-linux-$arch${NC}"
    
    if wget -q --show-progress "$download_url" -O /tmp/checkuser 2>/dev/null; then
        chmod +x /tmp/checkuser
        
        # Verificar que funciona ANTES de moverlo
        if /tmp/checkuser -version &>/dev/null 2>&1; then
            sudo mv /tmp/checkuser /usr/local/bin/checkuser
            echo -e "${OK} CheckUser ${latest_version} instalado exitosamente"
            return 0
        else
            rm -f /tmp/checkuser
            echo -e "${WARN} Binario descargado pero no ejecutable"
        fi
    fi
    
    # Probar nombres alternativos
    local alt_names=(
        "checkuser-$arch"
        "checkuser"
        "checkuser-linux"
    )
    
    for alt_name in "${alt_names[@]}"; do
        local alt_url="https://github.com/$selected_repo/releases/download/$latest_version/$alt_name"
        echo -e "${INFO} Probando: ${CYAN}$alt_name${NC}"
        
        if wget -q "$alt_url" -O /tmp/checkuser 2>/dev/null; then
            chmod +x /tmp/checkuser
            if /tmp/checkuser -version &>/dev/null 2>&1; then
                sudo mv /tmp/checkuser /usr/local/bin/checkuser
                echo -e "${OK} CheckUser instalado con nombre: $alt_name"
                return 0
            fi
            rm -f /tmp/checkuser
        fi
    done
    
    echo -e "${ERR} No se encontró binario funcional en $selected_repo"
    return 1
}

configure_checkuser_service() {
    echo -e "${INFO} Configurando servicio CheckUser (HTTP:2054)..."
    
    mkdir -p /etc/checkuser

    cat << EOF | sudo tee /etc/systemd/system/checkuser.service > /dev/null
[Unit]
Description=CheckUser Service
After=network.target nss-lookup.target

[Service]
User=root
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/checkuser -start -port 2054
Restart=always
RestartSec=5
WorkingDirectory=/etc/checkuser

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable checkuser &>/dev/null
    sudo systemctl restart checkuser
    sleep 2

    if systemctl is-active --quiet checkuser; then
        echo -e "${OK} CheckUser corriendo en puerto 2054 (interno)"
        return 0
    else
        echo -e "${ERR} Error al iniciar CheckUser"
        sudo journalctl -u checkuser -n 10 --no-pager
        return 1
    fi
}

configure_nginx_ssl() {
    local domain=$1
    
    echo -e "${INFO} Configurando nginx SSL proxy en puerto 2053..."
    
    # Eliminar configuración default
    sudo rm -f /etc/nginx/sites-enabled/default
    sudo rm -f /etc/nginx/conf.d/default.conf

    # Crear configuración nginx
    cat << EOF | sudo tee /etc/nginx/sites-enabled/checkuser.conf > /dev/null
server {
    listen 2053 ssl;
    server_name ${domain};

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    
    # Seguridad adicional
    add_header Strict-Transport-Security "max-age=31536000" always;
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;

    location / {
        proxy_pass http://127.0.0.1:2054;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Verificar configuración
    sudo nginx -t &>/dev/null
    if [[ $? -ne 0 ]]; then
        echo -e "${ERR} Error en configuración de nginx"
        sudo nginx -t
        return 1
    fi

    sudo systemctl enable nginx &>/dev/null
    sudo systemctl restart nginx
    sleep 1

    if systemctl is-active --quiet nginx; then
        echo -e "${OK} Nginx corriendo con SSL en puerto 2053"
        return 0
    else
        echo -e "${ERR} Error al iniciar nginx"
        sudo journalctl -u nginx -n 10 --no-pager
        return 1
    fi
}

generate_ssl_certificate() {
    local domain=$1
    local email=$2
    
    echo -e "${INFO} Generando certificado SSL para ${domain}..."
    
    # Verificar si ya existe
    if [[ -d "/etc/letsencrypt/live/${domain}" ]]; then
        echo -e "${WARN} Certificado existente para ${domain}, usando actual"
        return 0
    fi
    
    # Liberar puerto 80
    echo -e "${INFO} Liberando puerto 80..."
    sudo systemctl stop nginx &>/dev/null
    sudo systemctl stop apache2 &>/dev/null
    sudo systemctl stop httpd &>/dev/null
    
    # Matar cualquier proceso en puerto 80
    local pid_80
    pid_80=$(sudo ss -tlnp | grep ':80' | grep -oP 'pid=\K[0-9]+' | head -1)
    if [[ -n "$pid_80" ]]; then
        echo -e "${INFO} Cerrando proceso en puerto 80 (PID: $pid_80)..."
        sudo kill "$pid_80" 2>/dev/null
        sleep 2
    fi
    
    # Generar certificado
    sudo certbot certonly --standalone \
        -d "$domain" \
        --email "$email" \
        --agree-tos \
        --non-interactive \
        --quiet 2>/tmp/certbot_error.log
    
    if [[ $? -ne 0 ]]; then
        echo -e "${ERR} Error al generar certificado SSL"
        echo -e "${WARN} $(cat /tmp/certbot_error.log)"
        return 1
    fi
    
    echo -e "${OK} Certificado SSL generado exitosamente"
    return 0
}

configure_firewall() {
    echo -e "${INFO} Configurando firewall..."
    
        sudo iptables -I INPUT -p tcp --dport 2053 -j ACCEPT
        sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
        sudo iptables-save > /etc/iptables.rules
        
        echo -e "${OK} Puertos 2053 y 80 abiertos en iptables"
        
        echo -e "${WARN} iptables no está disponible. Abre puertos 2053 y 80 manualmente"
    fi
}

setup_auto_renewal() {
    local domain=$1
    
    echo -e "${INFO} Configurando renovación automática SSL..."
    
    # Crear script de renovación
    cat << EOF | sudo tee /etc/checkuser/renew-ssl.sh > /dev/null
#!/bin/bash
# Script de renovación automática SSL para CheckUser

# Liberar puerto 80
systemctl stop nginx 2>/dev/null
systemctl stop apache2 2>/dev/null

# Renovar certificado
certbot renew --quiet

# Reiniciar nginx
systemctl start nginx

echo "Certificado SSL renovado: \$(date)" >> /var/log/checkuser-ssl.log
EOF
    
    sudo chmod +x /etc/checkuser/renew-ssl.sh
    
    # Agregar al crontab
    (sudo crontab -l 2>/dev/null; echo "0 3 * * 1 /etc/checkuser/renew-ssl.sh") | sudo crontab - 2>/dev/null
    
    echo -e "${OK} Renovación automática configurada (cada lunes a las 3 AM)"
}

install_checkuser() {
    clear
    echo -e "${CYAN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║     CHECKUSER SSL INSTALLER v2.0         ║"
    echo "  ║     Proxy nginx + Let's Encrypt          ║"
    echo "  ║     Auto-detección última versión        ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"

    # Pedir dominio
    echo -e "${INFO} Ingresá el subdominio para checkuser:"
    echo -e "    (Ej: check.midominio.com)"
    read -rp "    Subdominio: " DOMAIN

    if [[ -z "$DOMAIN" ]]; then
        echo -e "${ERR} Dominio vacío. Volviendo al menú..."
        sleep 2
        return 1
    fi

    # Pedir email
    echo -e "${INFO} Ingresá tu email para Let's Encrypt:"
    read -rp "    Email: " EMAIL

    if [[ -z "$EMAIL" ]]; then
        echo -e "${ERR} Email vacío. Volviendo al menú..."
        sleep 2
        return 1
    fi

    # Verificar DNS
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || curl -s https://ipv4.icanhazip.com)
    DOMAIN_IP=$(dig +short "$DOMAIN" 2>/dev/null | tail -1)

    echo ""
    echo -e "${INFO} IP del servidor: ${CYAN}${SERVER_IP}${NC}"
    echo -e "${INFO} IP del dominio:  ${CYAN}${DOMAIN_IP}${NC}"

    if [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
        echo -e "${WARN} El dominio ${DOMAIN} no apunta a este servidor."
        echo -e "${WARN} Asegurate de que el registro A apunte a ${SERVER_IP}"
        read -rp "    ¿Continuar de todos modos? [s/N]: " CONT
        [[ "$CONT" != "s" && "$CONT" != "S" ]] && return 1
    fi

    echo ""
    echo -e "${INFO} Iniciando instalación para ${CYAN}${DOMAIN}${NC}..."
    echo ""

    # 1. Instalar dependencias
    install_dependencies || return 1

    # 2. Generar certificado SSL
    generate_ssl_certificate "$DOMAIN" "$EMAIL" || return 1

    # 3. Instalar CheckUser (siempre busca última versión)
    install_checkuser_binary || return 1

    # 4. Configurar servicio CheckUser (HTTP interno)
    configure_checkuser_service || return 1

    # 5. Configurar nginx como proxy SSL
    configure_nginx_ssl "$DOMAIN" || return 1

    # 6. Configurar firewall
    configure_firewall

    # 7. Configurar renovación automática
    setup_auto_renewal "$DOMAIN"

    # 8. Verificación final
    echo ""
    echo -e "${INFO} Verificando SSL..."
    sleep 3
    
    ISSUER=$(echo | openssl s_client -connect "${DOMAIN}:2053" 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null)

    echo ""
    if echo "$ISSUER" | grep -qi "Let's Encrypt\|R10\|R11\|R12"; then
        CHECKUSER_VERSION=$(/usr/local/bin/checkuser -version 2>&1 | grep -oP 'v[\d.]+' || echo "desconocida")
        
        echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║          INSTALACIÓN COMPLETADA ✓            ║${NC}"
        echo -e "${GREEN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC}  URL: ${CYAN}https://${DOMAIN}:2053${NC}"
        echo -e "${GREEN}║${NC}  SSL: ${GREEN}Let's Encrypt ✓${NC}"
        echo -e "${GREEN}║${NC}  Versión: ${CYAN}${CHECKUSER_VERSION}${NC}"
        echo -e "${GREEN}║${NC}  Puerto externo: ${CYAN}2053${NC} (nginx SSL)"
        echo -e "${GREEN}║${NC}  Puerto interno: ${CYAN}2054${NC} (checkuser HTTP)"
        echo -e "${GREEN}║${NC}  Renovación: ${GREEN}Automática${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
    else
        echo -e "${WARN} No se pudo verificar el certificado SSL"
    fi

    echo ""
    echo -e "Presiona Enter para continuar..."
    read
}

reinstall_checkuser() {
    echo -e "${YELLOW}🔄 Reinstalando CheckUser...${NC}"
    
    # Detener servicios
    sudo systemctl stop checkuser &>/dev/null
    sudo systemctl stop nginx &>/dev/null
    
    # Eliminar binario
    sudo rm -f /usr/local/bin/checkuser
    sudo rm -f /etc/systemd/system/checkuser.service
    
    sudo systemctl daemon-reload
    
    install_checkuser
}

uninstall_checkuser() {
    echo -e "${YELLOW}🗑️  Desinstalando CheckUser...${NC}"
    
    # Detener servicios
    sudo systemctl stop checkuser &>/dev/null
    sudo systemctl disable checkuser &>/dev/null
    sudo systemctl stop nginx &>/dev/null
    
    # Eliminar archivos
    sudo rm -f /usr/local/bin/checkuser
    sudo rm -f /etc/systemd/system/checkuser.service
    sudo rm -f /etc/nginx/sites-enabled/checkuser.conf
    sudo rm -rf /etc/checkuser
    
    # Preguntar si eliminar certificados
    read -rp "    ¿Eliminar certificados SSL? [s/N]: " DEL_SSL
    if [[ "$DEL_SSL" == "s" || "$DEL_SSL" == "S" ]]; then
        echo -e "${INFO} Dominios disponibles:"
        sudo ls /etc/letsencrypt/live/ 2>/dev/null
        read -rp "    Dominio a eliminar: " CERT_DOMAIN
        [[ -n "$CERT_DOMAIN" ]] && sudo certbot delete --cert-name "$CERT_DOMAIN" &>/dev/null
    fi
    
    sudo systemctl daemon-reload
    
    echo -e "${OK} CheckUser desinstalado correctamente"
    echo -e "\nPresiona Enter para continuar..."
    read
}

main() {
    while true; do
        clear
        echo -e "${CYAN}"
        echo '════════════════════════════════════'
        echo -ne "     CHECKUSER SSL INSTALLER v2.0"
        if systemctl is-active --quiet checkuser 2>/dev/null; then
            echo -e " ${GREEN}[ACTIVO]${NC}"
        else
            echo -e " ${RED}[INACTIVO]${NC}"
        fi
        echo '════════════════════════════════════'
        echo -e "${NC}"
        echo -e "${GREEN}[01]${NC} - INSTALAR CHECKUSER + SSL"
        echo -e "${GREEN}[02]${NC} - REINSTALAR CHECKUSER"
        echo -e "${GREEN}[03]${NC} - DESINSTALAR CHECKUSER"
        echo -e "${GREEN}[00]${NC} - SALIR"
        echo '════════════════════════════════════'
        echo -ne "${GREEN}Elige una opción: ${NC}"
        read option

        case $option in
            1|01) install_checkuser ;;
            2|02) reinstall_checkuser ;;
            3|03) uninstall_checkuser ;;
            0|00) echo "Saliendo..."; exit 0 ;;
            *) echo -e "${RED}Opción inválida${NC}"; sleep 2 ;;
        esac
    done
}

main
