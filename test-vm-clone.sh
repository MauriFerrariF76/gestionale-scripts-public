#!/bin/bash
# test-vm-clone.sh - Test automatico su cloni VM
# Versione: 1.0.0
# Descrizione: Script per testare il deploy automatico su cloni VM

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

# Verifica parametri
if [ $# -lt 2 ]; then
    echo "Uso: $0 <IP_VM> <NOME_TEST>"
    echo "Esempio: $0 10.10.10.44 test-script-automatico"
    exit 1
fi

VM_IP="$1"
TEST_NAME="$2"
SSH_PORT="${3:-22}"  # Porta SSH, default 22

# Funzione per test di connettività
test_connectivity() {
    log_info "Test connettività VM $VM_IP..."
    
    if ping -c 3 "$VM_IP" > /dev/null 2>&1; then
        log_success "Ping a $VM_IP: OK"
    else
        log_error "Ping a $VM_IP: FALLITO"
        return 1
    fi
}

# Funzione per test SSH
test_ssh() {
    log_info "Test SSH su porta $SSH_PORT..."
    
    if ssh -p "$SSH_PORT" -o ConnectTimeout=10 -o BatchMode=yes mauri@"$VM_IP" "echo 'SSH OK'" > /dev/null 2>&1; then
        log_success "SSH a $VM_IP:$SSH_PORT: OK"
    else
        log_error "SSH a $VM_IP:$SSH_PORT: FALLITO"
        return 1
    fi
}

# Funzione per download script
download_script() {
    log_info "Download script automatico su VM..."
    
    ssh -p "$SSH_PORT" mauri@"$VM_IP" << 'EOF'
cd /home/mauri
mkdir -p gestionale-fullstack
cd gestionale-fullstack
wget https://raw.githubusercontent.com/MauriFerrariF76/gestionale-fullstack/main/scripts/install-gestionale-completo.sh
chmod +x install-gestionale-completo.sh
echo "Script scaricato e reso eseguibile"
EOF
    
    if [ $? -eq 0 ]; then
        log_success "Script scaricato su VM"
    else
        log_error "Download script fallito"
        return 1
    fi
}

# Funzione per esecuzione deploy automatico
run_deploy() {
    log_info "Esecuzione deploy automatico su VM..."
    
    ssh -p "$SSH_PORT" mauri@"$VM_IP" << 'EOF'
cd /home/mauri/gestionale-fullstack
sudo ./install-gestionale-completo.sh
EOF
    
    if [ $? -eq 0 ]; then
        log_success "Deploy automatico completato"
    else
        log_error "Deploy automatico fallito"
        return 1
    fi
}

# Funzione per test post-deploy
test_post_deploy() {
    log_info "Test post-deploy su VM..."
    
    # Test container
    ssh -p "$SSH_PORT" mauri@"$VM_IP" "docker ps" | grep -q "Up" && log_success "Container attivi" || log_error "Container non attivi"
    
    # Test backend
    ssh -p "$SSH_PORT" mauri@"$VM_IP" "curl -s http://localhost:3001/health" | grep -q "ok" && log_success "Backend OK" || log_error "Backend non risponde"
    
    # Test frontend
    ssh -p "$SSH_PORT" mauri@"$VM_IP" "curl -s http://localhost:3000" | grep -q "html" && log_success "Frontend OK" || log_error "Frontend non risponde"
    
    # Test SSH porta 27
    ssh -p "$SSH_PORT" mauri@"$VM_IP" "sudo ss -tuln | grep :27" && log_success "SSH porta 27 configurato" || log_warning "SSH porta 27 non configurato"
    
    # Test LVM
    ssh -p "$SSH_PORT" mauri@"$VM_IP" "sudo lvs 2>/dev/null || echo 'LVM non attivo'" | grep -q "LVM non attivo" && log_success "LVM non attivo (corretto)" || log_error "LVM attivo (problema)"
}

# Funzione per test accesso esterno
test_external_access() {
    log_info "Test accesso esterno..."
    
    # Test backend esterno
    if curl -s "http://$VM_IP:3001/health" | grep -q "ok"; then
        log_success "Backend accessibile esternamente"
    else
        log_error "Backend non accessibile esternamente"
    fi
    
    # Test frontend esterno
    if curl -s "http://$VM_IP:3000" | grep -q "html"; then
        log_success "Frontend accessibile esternamente"
    else
        log_error "Frontend non accessibile esternamente"
    fi
    
    # Test SSH esterno
    if ssh -p 27 -o ConnectTimeout=5 -o BatchMode=yes mauri@"$VM_IP" "echo 'SSH esterno OK'" > /dev/null 2>&1; then
        log_success "SSH esterno su porta 27 OK"
    else
        log_warning "SSH esterno su porta 27 non funziona"
    fi
}

# Funzione per generazione report
generate_report() {
    log_info "Generazione report test..."
    
    REPORT_FILE="test-report-$TEST_NAME-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$REPORT_FILE" << EOF
=== REPORT TEST VM CLONE ===
Test: $TEST_NAME
VM IP: $VM_IP
Data: $(date)
SSH Porta: $SSH_PORT

=== CONFIGURAZIONE VM ===
$(ssh -p "$SSH_PORT" mauri@"$VM_IP" "hostname && whoami && ip addr show")

=== CONTAINER ATTIVI ===
$(ssh -p "$SSH_PORT" mauri@"$VM_IP" "docker ps")

=== TEST CONNETTIVITÀ ===
Ping: $(ping -c 1 "$VM_IP" 2>/dev/null | grep "1 packets transmitted" || echo "FALLITO")
SSH: $(ssh -p "$SSH_PORT" -o ConnectTimeout=5 -o BatchMode=yes mauri@"$VM_IP" "echo 'OK'" 2>/dev/null || echo "FALLITO")

=== TEST SERVIZI ===
Backend: $(curl -s "http://$VM_IP:3001/health" 2>/dev/null || echo "NON ACCESSIBILE")
Frontend: $(curl -s "http://$VM_IP:3000" 2>/dev/null | head -1 || echo "NON ACCESSIBILE")

=== CONFIGURAZIONE SISTEMA ===
LVM: $(ssh -p "$SSH_PORT" mauri@"$VM_IP" "sudo lvs 2>/dev/null || echo 'NON ATTIVO'")
SSH Porta 27: $(ssh -p "$SSH_PORT" mauri@"$VM_IP" "sudo ss -tuln | grep :27" || echo "NON CONFIGURATO")

=== RISULTATO TEST ===
$(if [ $? -eq 0 ]; then echo "✅ TEST COMPLETATO CON SUCCESSO"; else echo "❌ TEST FALLITO"; fi)
EOF
    
    log_success "Report generato: $REPORT_FILE"
}

# Funzione principale
main() {
    echo "=========================================="
    echo "TEST VM CLONE - $TEST_NAME"
    echo "VM IP: $VM_IP"
    echo "SSH Porta: $SSH_PORT"
    echo "Data: $(date)"
    echo "=========================================="
    echo ""
    
    # Esegui test in sequenza
    test_connectivity || exit 1
    test_ssh || exit 1
    download_script || exit 1
    run_deploy || exit 1
    test_post_deploy
    test_external_access
    generate_report
    
    echo ""
    echo "=========================================="
    echo "TEST COMPLETATO: $TEST_NAME"
    echo "=========================================="
}

# Esecuzione script
main "$@" 