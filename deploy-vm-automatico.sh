#!/bin/bash
# deploy-vm-automatico.sh - Deploy automatico completo su VM
# Versione: 1.0
# Descrizione: Automatizza completamente il deploy sulla VM gestendo password e sudo

set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configurazione
VM_IP="10.10.10.43"
VM_USER="mauri"
VM_PASSWORD="FER384wlJ"
SSH_KEY="$HOME/.ssh/id_rsa_vm"
PROJECT_DIR="/home/mauri/gestionale-fullstack"

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

# Funzione per eseguire comando SSH con password
ssh_with_password() {
    local cmd="$1"
    sshpass -p "$VM_PASSWORD" ssh -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" "$cmd"
}

# Funzione per eseguire comando SSH con chiave
ssh_with_key() {
    local cmd="$1"
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" "$cmd"
}

# Funzione per eseguire comando sudo con password
sudo_with_password() {
    local cmd="$1"
    sshpass -p "$VM_PASSWORD" ssh -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" "echo '$VM_PASSWORD' | sudo -S $cmd"
}

# Funzione per eseguire comando sudo con sshpass
sudo_with_sshpass() {
    local cmd="$1"
    sshpass -p "$VM_PASSWORD" ssh -o StrictHostKeyChecking=no "$VM_USER@$VM_IP" "sudo -S $cmd"
}

# Verifica prerequisiti
check_prerequisites() {
    log_info "=== VERIFICA PREREQUISITI ==="
    
    # Verifica sshpass
    if ! command -v sshpass &> /dev/null; then
        log_info "Installazione sshpass..."
        sudo apt install sshpass -y
    fi
    
    # Verifica connessione VM
    if ping -c 1 $VM_IP &> /dev/null; then
        log_success "VM raggiungibile: $VM_IP"
    else
        log_error "VM non raggiungibile: $VM_IP"
        exit 1
    fi
    
    # Test SSH con password
    if ssh_with_password "echo 'SSH con password OK'" &> /dev/null; then
        log_success "SSH con password funzionante"
    else
        log_error "SSH con password non funzionante"
        exit 1
    fi
}

# Configurazione SSH senza password
setup_ssh_keys() {
    log_info "=== CONFIGURAZIONE SSH SENZA PASSWORD ==="
    
    # Genera chiave SSH se non esiste
    if [ ! -f "$SSH_KEY" ]; then
        log_info "Generazione chiave SSH..."
        ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N ""
    fi
    
    # Copia chiave sulla VM
    log_info "Copia chiave SSH sulla VM..."
    sshpass -p "$VM_PASSWORD" ssh-copy-id -i "$SSH_KEY.pub" "$VM_USER@$VM_IP"
    
    # Test SSH con chiave
    if ssh_with_key "echo 'SSH con chiave OK'" &> /dev/null; then
        log_success "SSH senza password configurato"
    else
        log_error "Configurazione SSH fallita"
        exit 1
    fi
}

# Configurazione sudo senza password
setup_sudo_nopasswd() {
    log_info "=== CONFIGURAZIONE SUDO SENZA PASSWORD ==="
    
    # Crea file sudoers temporaneo
    local sudoers_content="$VM_USER ALL=(ALL) NOPASSWD: ALL"
    
    # Copia file sudoers sulla VM usando sshpass
    echo "$sudoers_content" | sudo_with_sshpass "tee /etc/sudoers.d/$VM_USER"
    
    # Test sudo senza password
    if ssh_with_key "sudo echo 'Sudo senza password OK'" &> /dev/null; then
        log_success "Sudo senza password configurato"
    else
        log_error "Configurazione sudo fallita"
        exit 1
    fi
}

# Preparazione ambiente VM
prepare_vm_environment() {
    log_info "=== PREPARAZIONE AMBIENTE VM ==="
    
    # Crea directory progetto
    ssh_with_key "mkdir -p $PROJECT_DIR"
    
    # Copia script di installazione
    log_info "Copia script di installazione..."
    scp -i "$SSH_KEY" scripts/install-gestionale-completo.sh "$VM_USER@$VM_IP:$PROJECT_DIR/"
    
    # Rendi eseguibile
    ssh_with_key "chmod +x $PROJECT_DIR/install-gestionale-completo.sh"
    
    log_success "Ambiente VM preparato"
}

# Esecuzione deploy automatico
run_deploy() {
    log_info "=== ESECUZIONE DEPLOY AUTOMATICO ==="
    
    log_info "Avvio script di installazione..."
    
    # Esegui deploy in background e monitora
    ssh_with_key "cd $PROJECT_DIR && nohup sudo ./install-gestionale-completo.sh > deploy.log 2>&1 &"
    
    # Attendi un momento per l'avvio
    sleep 5
    
    # Monitora il processo
    local deploy_pid=""
    local attempts=0
    local max_attempts=60  # 5 minuti
    
    while [ $attempts -lt $max_attempts ]; do
        deploy_pid=$(ssh_with_key "ps aux | grep install-gestionale-completo.sh | grep -v grep | awk '{print \$2}'")
        
        if [ -n "$deploy_pid" ]; then
            log_info "Deploy in corso... (PID: $deploy_pid)"
            sleep 30  # Controlla ogni 30 secondi
            attempts=$((attempts + 1))
        else
            log_info "Deploy completato o terminato"
            break
        fi
    done
    
    if [ $attempts -eq $max_attempts ]; then
        log_warning "Timeout deploy - verificare manualmente"
    fi
}

# Verifica post-deploy
verify_deploy() {
    log_info "=== VERIFICA POST-DEPLOY ==="
    
    # Verifica Docker
    local docker_status=$(ssh_with_key "docker --version 2>/dev/null || echo 'Docker non installato'")
    echo "Docker: $docker_status"
    
    # Verifica Node.js
    local node_status=$(ssh_with_key "node --version 2>/dev/null || echo 'Node.js non installato'")
    echo "Node.js: $node_status"
    
    # Verifica container
    local containers=$(ssh_with_key "docker ps 2>/dev/null || echo 'Docker non disponibile'")
    echo "Container attivi:"
    echo "$containers"
    
    # Test applicazione
    local backend_test=$(ssh_with_key "curl -s http://localhost:3001/health 2>/dev/null || echo 'Backend non raggiungibile'")
    echo "Backend test: $backend_test"
    
    local frontend_test=$(ssh_with_key "curl -s http://localhost:3000 2>/dev/null | head -c 100 || echo 'Frontend non raggiungibile'")
    echo "Frontend test: $frontend_test"
    
    # Test accesso esterno
    local external_backend=$(curl -s http://$VM_IP:3001/health 2>/dev/null || echo "Backend non accessibile esternamente")
    echo "Backend esterno: $external_backend"
    
    local external_frontend=$(curl -s http://$VM_IP:3000 2>/dev/null | head -c 100 || echo "Frontend non accessibile esternamente")
    echo "Frontend esterno: $external_frontend"
}

# Genera report
generate_report() {
    log_info "=== GENERAZIONE REPORT ==="
    
    local report_file="vm-deploy-automatico-report-$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
=== VM DEPLOY AUTOMATICO REPORT ===
Data: $(date)
VM: $VM_IP
PC Sorgente: $(hostname -I | awk '{print $1}')

=== CONFIGURAZIONE ===
SSH senza password: $(ssh_with_key "echo 'OK'" 2>/dev/null && echo "Configurato" || echo "Non configurato")
Sudo senza password: $(ssh_with_key "sudo echo 'OK'" 2>/dev/null && echo "Configurato" || echo "Non configurato")

=== SERVIZI INSTALLATI ===
Docker: $(ssh_with_key "docker --version 2>/dev/null || echo 'Non installato'")
Node.js: $(ssh_with_key "node --version 2>/dev/null || echo 'Non installato'")

=== CONTAINER DOCKER ===
$(ssh_with_key "docker ps 2>/dev/null || echo 'Docker non disponibile'")

=== TEST APPLICAZIONE ===
Backend: $(ssh_with_key "curl -s http://localhost:3001/health 2>/dev/null || echo 'Non raggiungibile'")
Frontend: $(ssh_with_key "curl -s http://localhost:3000 2>/dev/null | head -c 50 || echo 'Non raggiungibile'")

=== TEST ESTERNO ===
Backend esterno: $(curl -s http://$VM_IP:3001/health 2>/dev/null || echo 'Non accessibile')
Frontend esterno: $(curl -s http://$VM_IP:3000 2>/dev/null | head -c 50 || echo 'Non accessibile')

=== LOG DEPLOY ===
$(ssh_with_key "tail -n 20 $PROJECT_DIR/deploy.log 2>/dev/null || echo 'Log non disponibile'")

EOF
    
    log_success "Report generato: $report_file"
}

# Menu principale
show_menu() {
    echo -e "${BLUE}=== DEPLOY AUTOMATICO VM ===${NC}"
    echo ""
    echo "1. Verifica prerequisiti"
    echo "2. Configura SSH senza password"
    echo "3. Configura sudo senza password"
    echo "4. Prepara ambiente VM"
    echo "5. Esegui deploy automatico"
    echo "6. Verifica post-deploy"
    echo "7. Genera report"
    echo "8. Deploy completo automatico"
    echo "0. Esci"
    echo ""
    read -p "Seleziona opzione: " choice
}

# Deploy completo automatico
run_full_deploy() {
    log_info "=== DEPLOY COMPLETO AUTOMATICO ==="
    
    check_prerequisites
    setup_ssh_keys
    setup_sudo_nopasswd
    prepare_vm_environment
    run_deploy
    sleep 60  # Attendi 1 minuto per il completamento
    verify_deploy
    generate_report
    
    log_success "Deploy completo automatico completato!"
}

# Main
main() {
    if [ "$1" = "--full" ]; then
        run_full_deploy
        exit 0
    fi
    
    while true; do
        show_menu
        case $choice in
            1) check_prerequisites ;;
            2) setup_ssh_keys ;;
            3) setup_sudo_nopasswd ;;
            4) prepare_vm_environment ;;
            5) run_deploy ;;
            6) verify_deploy ;;
            7) generate_report ;;
            8) run_full_deploy ;;
            0) echo "Arrivederci!"; exit 0 ;;
            *) echo "Opzione non valida" ;;
        esac
        
        echo ""
        read -p "Premi Invio per continuare..."
    done
}

# Esegui main
main "$@" 