#!/bin/bash
# install-gestionale-completo.sh - Installazione automatica Gestionale
# Versione: 2.0.0
# Basato su: Server fisico 10.10.10.15 (configurazione ideale)
# SSH Porta: 27

set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Funzioni di utilità
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Verifica prerequisiti
check_prerequisites() {
    log_info "=== VERIFICA PREREQUISITI ==="
    
    # Verifica sistema operativo
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        if [[ "$ID" == "ubuntu" && "$VERSION_ID" == "24.04" ]]; then
            log_success "Sistema operativo: Ubuntu 24.04.2 LTS"
        else
            log_warning "Sistema operativo: $PRETTY_NAME (non testato)"
        fi
    fi
    
    # Verifica privilegi
    if [ "$EUID" -ne 0 ]; then
        log_error "Esegui questo script con privilegi di amministratore"
        echo "   sudo ./install-gestionale-completo.sh"
        exit 1
    fi
    
    # Verifica memoria (min 2GB)
    MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$MEMORY_GB" -lt 2 ]; then
        log_error "Memoria insufficiente: ${MEMORY_GB}GB (minimo 2GB)"
        exit 1
    else
        log_success "Memoria: ${MEMORY_GB}GB"
    fi
    
    # Verifica spazio disco (min 3GB per VM di test)
    DISK_GB=$(df -BG / | awk 'NR==2{print $4}' | sed 's/G//')
    if [ "$DISK_GB" -lt 3 ]; then
        log_error "Spazio disco insufficiente: ${DISK_GB}GB (minimo 3GB per VM di test)"
        exit 1
    else
        log_success "Spazio disco: ${DISK_GB}GB"
    fi
    
    log_success "Prerequisiti verificati"
    echo ""
}

# Aggiornamento sistema
update_system() {
    log_info "=== AGGIORNAMENTO SISTEMA ==="
    
    log_info "Aggiornamento pacchetti..."
    apt update
    apt upgrade -y
    
    log_info "Installazione pacchetti essenziali..."
    apt install -y curl wget git vim htop unzip net-tools build-essential
    
    log_info "Installazione pacchetti per sviluppo e build..."
    apt install -y python3 python3-pip python3-venv
    
    log_info "Installazione pacchetti per database..."
    apt install -y postgresql-client
    
    log_info "Installazione pacchetti per SSL/HTTPS..."
    apt install -y certbot python3-certbot-nginx
    
    log_info "Installazione pacchetti per monitoraggio..."
    apt install -y htop iotop nethogs
    
    log_success "Sistema aggiornato"
    echo ""
}

# Installazione Docker (versione corretta)
install_docker() {
    log_info "=== INSTALLAZIONE DOCKER ==="
    
    log_info "Rimozione versioni precedenti..."
    apt remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    log_info "Installazione prerequisiti Docker..."
    apt install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    log_info "Aggiunta repository Docker..."
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    log_info "Aggiornamento pacchetti..."
    apt update
    
    log_info "Installazione Docker..."
    apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    
    log_info "Avvio e abilitazione Docker..."
    systemctl start docker
    systemctl enable docker
    
    log_info "Installazione Docker Compose standalone..."
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
    
    log_info "Configurazione utente Docker..."
    usermod -aG docker mauri
    
    # Verifica installazione
    DOCKER_VERSION=$(docker --version)
    COMPOSE_VERSION=$(docker-compose --version)
    
    log_success "Docker installato: $DOCKER_VERSION"
    log_success "Docker Compose: $COMPOSE_VERSION"
    log_success "Docker configurato"
    echo ""
}

# Configurazione rete
configure_network() {
    log_info "=== CONFIGURAZIONE RETE ==="
    
    # Configurazione IP statico (da personalizzare)
    log_info "Configurazione IP statico..."
    cat > /etc/netplan/01-static-ip.yaml << EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    enp4s0:
      dhcp4: false
      addresses:
        - 10.10.10.15/24
      gateway4: 10.10.10.1
      nameservers:
        addresses: [8.8.8.8, 1.1.1.1]
EOF
    
    log_info "Applicazione configurazione rete..."
    netplan apply
    
    log_success "Rete configurata"
    echo ""
}

# Configurazione SSH
configure_ssh() {
    log_info "=== CONFIGURAZIONE SSH ==="
    
    log_info "Configurazione SSH su porta 27..."
    
    # Backup configurazione originale
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    # Modifica configurazione SSH
    sed -i 's/#Port 22/Port 27/' /etc/ssh/sshd_config
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config
    
    log_info "Riavvio servizio SSH..."
    systemctl restart ssh
    
    log_success "SSH configurato su porta 27"
    echo ""
}

# Configurazione firewall
configure_firewall() {
    log_info "=== CONFIGURAZIONE FIREWALL ==="
    
    log_info "Configurazione UFW..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 27/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw allow 5433/tcp comment 'PostgreSQL'
    ufw --force enable
    
    log_success "Firewall configurato"
    echo ""
}

# Clonazione repository (versione corretta)
clone_repository() {
    log_info "=== CLONAZIONE REPOSITORY ==="
    
    cd /home/mauri
    
    # Rimuovi directory esistente se presente
    if [ -d "gestionale-fullstack" ]; then
        log_info "Rimozione directory esistente..."
        rm -rf gestionale-fullstack
    fi
    
    log_info "Clonazione repository gestionale..."
    git clone https://github.com/MauriFerrariF76/gestionale-fullstack.git
    
    if [ $? -eq 0 ]; then
        log_success "Repository clonato con successo"
    else
        log_error "Errore durante la clonazione del repository"
        exit 1
    fi
    
    cd gestionale-fullstack
    
    log_success "Repository configurato"
    echo ""
}

# Setup applicazione
setup_application() {
    log_info "=== SETUP APPLICAZIONE ==="
    
    cd /home/mauri/gestionale-fullstack
    
    log_info "Setup variabili d'ambiente..."
    if [ ! -f ".env" ]; then
        cp .env.example .env 2>/dev/null || echo "# Configurazione ambiente" > .env
    fi
    
    log_info "Setup segreti Docker..."
    mkdir -p secrets
    echo "gestionale2025" > secrets/db_password.txt
    echo "GestionaleFerrari2025JWT_UltraSecure_v1!" > secrets/jwt_secret.txt
    chmod 600 secrets/*.txt
    
    log_info "Build e avvio container..."
    docker compose up -d --build
    
    log_success "Applicazione configurata"
    echo ""
}

# Configurazione SSL/HTTPS (opzionale)
setup_ssl() {
    log_info "=== CONFIGURAZIONE SSL/HTTPS ==="
    
    log_info "Verifica dominio..."
    DOMAIN="gestionale.carpenteriaferrari.com"
    
    # Verifica se il dominio è configurato
    if nslookup $DOMAIN > /dev/null 2>&1; then
        log_info "Dominio $DOMAIN risolto correttamente"
        
        log_info "Installazione Certbot..."
        apt install -y certbot python3-certbot-nginx
        
        log_info "Configurazione SSL con Let's Encrypt..."
        # Certbot per Nginx dockerizzato (certificati in /etc/letsencrypt)
        certbot certonly --standalone -d $DOMAIN --non-interactive --agree-tos --email admin@carpenteriaferrari.com
        
        if [ $? -eq 0 ]; then
            log_success "SSL configurato per $DOMAIN"
            log_info "Certificati salvati in /etc/letsencrypt/"
            
            # Test HTTPS dopo riavvio container
            log_info "Riavvio container per applicare SSL..."
            cd /home/mauri/gestionale-fullstack
            docker compose restart nginx
            
            # Test HTTPS
            sleep 10
            if curl -s -o /dev/null -w "%{http_code}" https://$DOMAIN | grep -q "200\|301\|302"; then
                log_success "HTTPS funzionante"
            else
                log_warning "HTTPS non testato (dominio non accessibile)"
            fi
        else
            log_warning "SSL non configurato (dominio non accessibile o errore)"
        fi
    else
        log_warning "Dominio $DOMAIN non risolto - SSL non configurato"
        log_info "Per configurare SSL:"
        log_info "1. Configura il DNS per puntare a questo server"
        log_info "2. Esegui: sudo certbot certonly --standalone -d $DOMAIN"
    fi
    
    echo ""
}

# Verifiche post-installazione
post_install_checks() {
    log_info "=== VERIFICHE POST-INSTALLAZIONE ==="
    
    log_info "Verifica Docker..."
    if command -v docker > /dev/null && command -v docker-compose > /dev/null; then
        log_success "Docker: $(docker --version)"
        log_success "Docker Compose: $(docker-compose --version)"
    else
        log_error "Docker o Docker Compose non installati"
    fi
    
    log_info "Verifica Docker daemon..."
    if docker ps > /dev/null 2>&1; then
        log_success "Docker daemon attivo"
    else
        log_warning "Docker daemon non attivo"
    fi
    
    log_info "Verifica pacchetti sistema..."
    if command -v postgres > /dev/null; then
        log_success "PostgreSQL client: installato"
    else
        log_warning "PostgreSQL client non installato"
    fi
    
    if command -v certbot > /dev/null; then
        log_success "Certbot: installato"
    else
        log_warning "Certbot non installato"
    fi
    
    log_info "Verifica servizi Docker..."
    if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "Up"; then
        log_success "Container attivi"
        docker ps --format "table {{.Names}}\t{{.Status}}"
    else
        log_error "Nessun container attivo"
    fi
    
    log_info "Verifica connettività..."
    if ping -c 3 8.8.8.8 > /dev/null 2>&1; then
        log_success "Connettività internet OK"
    else
        log_warning "Connettività internet non verificata"
    fi
    
    log_info "Verifica porte in ascolto..."
    ss -tuln | grep -E ":(27|80|443|5433)"
    
    log_success "Verifiche completate"
    echo ""
}

# Generazione report
generate_report() {
    log_info "=== GENERAZIONE REPORT ==="
    
    REPORT_FILE="/home/mauri/install-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$REPORT_FILE" << EOF
=== REPORT INSTALLAZIONE GESTIONALE ===
Data: $(date)
Sistema: $(lsb_release -d | cut -f2)
Kernel: $(uname -r)
IP: $(ip route get 8.8.8.8 | awk '{print $7}')
SSH Porta: 27
Docker: $(docker --version)
Docker Compose: $(docker-compose --version)

=== CONTAINER ATTIVI ===
$(docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}")

=== CONFIGURAZIONE COMPLETATA ===
✅ Sistema aggiornato
✅ Rete configurata
✅ SSH su porta 27
✅ Firewall configurato
✅ Docker installato
✅ Repository clonato
✅ Applicazione avviata

=== ACCESSO APPLICAZIONE ===
Frontend: http://$(ip route get 8.8.8.8 | awk '{print $7}'):3000
Backend: http://$(ip route get 8.8.8.8 | awk '{print $7}'):3001
Database: $(ip route get 8.8.8.8 | awk '{print $7}'):5433

=== COMANDI UTILI ===
Stato container: docker ps
Log container: docker-compose logs -f
Ferma servizi: docker-compose down
Avvia servizi: docker-compose up -d
EOF
    
    log_success "Report generato: $REPORT_FILE"
    echo ""
}

# Funzione principale
main() {
    echo "=========================================="
    echo "INSTALLAZIONE AUTOMATICA GESTIONALE"
    echo "Versione: 2.0.0"
    echo "Basato su: Server fisico 10.10.10.15"
    echo "SSH Porta: 27"
    echo "Data: $(date)"
    echo "=========================================="
    echo ""
    
    check_prerequisites
    update_system
    install_docker
    configure_network
    configure_ssh
    configure_firewall
    clone_repository
    setup_application
    setup_ssl
    post_install_checks
    generate_report
    
    echo "=========================================="
    echo "INSTALLAZIONE COMPLETATA CON SUCCESSO!"
    echo "=========================================="
    echo ""
    echo "🎉 Il gestionale è ora operativo!"
    echo ""
    echo "📋 Prossimi passi:"
    echo "1. Configura le variabili d'ambiente in .env"
    echo "2. Accedi all'applicazione via browser"
    echo "3. Configura backup e monitoraggio"
    echo ""
    echo "📞 Supporto: Consulta la documentazione in /docs"
}

# Esecuzione script
main "$@" 