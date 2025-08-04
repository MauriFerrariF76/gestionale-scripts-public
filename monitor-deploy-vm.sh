#!/bin/bash
# monitor-deploy-vm.sh - Monitoraggio deploy automatico VM
# Versione: 1.0

set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configurazione
VM_IP="10.10.10.43"
PC_IP="10.10.10.33"

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

# Verifica connessione VM
check_vm_connection() {
    log_info "=== VERIFICA CONNESSIONE VM ==="
    
    if ping -c 1 $VM_IP &> /dev/null; then
        log_success "VM raggiungibile: $VM_IP"
    else
        log_error "VM non raggiungibile: $VM_IP"
        return 1
    fi
    
    if ssh -o ConnectTimeout=5 mauri@$VM_IP "echo 'SSH OK'" &> /dev/null; then
        log_success "SSH funzionante"
    else
        log_error "SSH non funzionante"
        return 1
    fi
}

# Verifica processo installazione
check_install_process() {
    log_info "=== VERIFICA PROCESSO INSTALLAZIONE ==="
    
    # Verifica se lo script è in esecuzione
    local script_running=$(ssh mauri@$VM_IP "ps aux | grep install-gestionale-completo.sh | grep -v grep" 2>/dev/null || echo "")
    
    if [ -n "$script_running" ]; then
        log_info "Script di installazione in esecuzione..."
        echo "$script_running"
    else
        log_warning "Script di installazione non in esecuzione"
    fi
    
    # Verifica log recenti
    log_info "Log recenti sistema:"
    ssh mauri@$VM_IP "tail -n 10 /var/log/syslog" 2>/dev/null || echo "Impossibile leggere log"
}

# Verifica servizi installati
check_installed_services() {
    log_info "=== VERIFICA SERVIZI INSTALLATI ==="
    
    # Verifica Docker
    local docker_status=$(ssh mauri@$VM_IP "docker --version 2>/dev/null || echo 'Docker non installato'")
    echo "Docker: $docker_status"
    
    # Verifica Node.js
    local node_status=$(ssh mauri@$VM_IP "node --version 2>/dev/null || echo 'Node.js non installato'")
    echo "Node.js: $node_status"
    
    # Verifica directory progetto
    local project_dir=$(ssh mauri@$VM_IP "ls -la /home/mauri/gestionale-fullstack/ 2>/dev/null || echo 'Directory non trovata'")
    echo "Directory progetto:"
    echo "$project_dir"
}

# Verifica porte in ascolto
check_listening_ports() {
    log_info "=== VERIFICA PORTE IN ASCOLTO ==="
    
    local ports=$(ssh mauri@$VM_IP "sudo ss -tuln | grep -E ':(22|27|80|443|3000|3001|5433)'" 2>/dev/null || echo "Impossibile verificare porte")
    echo "Porte in ascolto:"
    echo "$ports"
}

# Verifica container Docker
check_docker_containers() {
    log_info "=== VERIFICA CONTAINER DOCKER ==="
    
    local containers=$(ssh mauri@$VM_IP "docker ps 2>/dev/null || echo 'Docker non disponibile'")
    echo "Container attivi:"
    echo "$containers"
}

# Test accesso applicazione
test_application_access() {
    log_info "=== TEST ACCESSO APPLICAZIONE ==="
    
    # Test backend
    local backend_test=$(ssh mauri@$VM_IP "curl -s http://localhost:3001/health 2>/dev/null || echo 'Backend non raggiungibile'")
    echo "Backend test: $backend_test"
    
    # Test frontend
    local frontend_test=$(ssh mauri@$VM_IP "curl -s http://localhost:3000 2>/dev/null | head -c 100 || echo 'Frontend non raggiungibile'")
    echo "Frontend test: $frontend_test"
}

# Test accesso esterno
test_external_access() {
    log_info "=== TEST ACCESSO ESTERNO ==="
    
    # Test da PC-MAURI
    local external_backend=$(curl -s http://$VM_IP:3001/health 2>/dev/null || echo "Backend non accessibile esternamente")
    echo "Backend esterno: $external_backend"
    
    local external_frontend=$(curl -s http://$VM_IP:3000 2>/dev/null | head -c 100 || echo "Frontend non accessibile esternamente")
    echo "Frontend esterno: $external_frontend"
}

# Genera report
generate_report() {
    log_info "=== GENERAZIONE REPORT ==="
    
    local report_file="vm-deploy-report-$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$report_file" << EOF
=== VM DEPLOY REPORT ===
Data: $(date)
VM: $VM_IP
PC Sorgente: $PC_IP

=== STATO CONNESSIONE ===
$(ping -c 1 $VM_IP 2>/dev/null | grep "1 packets" || echo "VM non raggiungibile")

=== SERVIZI INSTALLATI ===
Docker: $(ssh mauri@$VM_IP "docker --version 2>/dev/null || echo 'Non installato'")
Node.js: $(ssh mauri@$VM_IP "node --version 2>/dev/null || echo 'Non installato'")

=== CONTAINER DOCKER ===
$(ssh mauri@$VM_IP "docker ps 2>/dev/null || echo 'Docker non disponibile'")

=== PORTE IN ASCOLTO ===
$(ssh mauri@$VM_IP "sudo ss -tuln | grep -E ':(22|27|80|443|3000|3001|5433)' 2>/dev/null || echo 'Impossibile verificare')

=== TEST APPLICAZIONE ===
Backend: $(ssh mauri@$VM_IP "curl -s http://localhost:3001/health 2>/dev/null || echo 'Non raggiungibile'")
Frontend: $(ssh mauri@$VM_IP "curl -s http://localhost:3000 2>/dev/null | head -c 50 || echo 'Non raggiungibile'")

=== TEST ESTERNO ===
Backend esterno: $(curl -s http://$VM_IP:3001/health 2>/dev/null || echo 'Non accessibile')
Frontend esterno: $(curl -s http://$VM_IP:3000 2>/dev/null | head -c 50 || echo 'Non accessibile')

EOF
    
    log_success "Report generato: $report_file"
}

# Menu principale
show_menu() {
    echo -e "${BLUE}=== MONITORAGGIO DEPLOY VM ===${NC}"
    echo ""
    echo "1. Verifica connessione VM"
    echo "2. Verifica processo installazione"
    echo "3. Verifica servizi installati"
    echo "4. Verifica porte in ascolto"
    echo "5. Verifica container Docker"
    echo "6. Test accesso applicazione"
    echo "7. Test accesso esterno"
    echo "8. Genera report completo"
    echo "9. Monitoraggio completo"
    echo "0. Esci"
    echo ""
    read -p "Seleziona opzione: " choice
}

# Monitoraggio completo
run_full_monitoring() {
    log_info "=== MONITORAGGIO COMPLETO ==="
    
    check_vm_connection
    check_install_process
    check_installed_services
    check_listening_ports
    check_docker_containers
    test_application_access
    test_external_access
    generate_report
    
    log_success "Monitoraggio completo completato!"
}

# Main
main() {
    if [ "$1" = "--full" ]; then
        run_full_monitoring
        exit 0
    fi
    
    while true; do
        show_menu
        case $choice in
            1) check_vm_connection ;;
            2) check_install_process ;;
            3) check_installed_services ;;
            4) check_listening_ports ;;
            5) check_docker_containers ;;
            6) test_application_access ;;
            7) test_external_access ;;
            8) generate_report ;;
            9) run_full_monitoring ;;
            0) echo "Arrivederci!"; exit 0 ;;
            *) echo "Opzione non valida" ;;
        esac
        
        echo ""
        read -p "Premi Invio per continuare..."
    done
}

# Esegui main
main "$@" 