#!/bin/bash
# deploy-docker-ottimizzato.sh - Deploy ottimizzato con Docker
# Versione: 1.0.0

set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

echo "=== DEPLOY DOCKER OTTIMIZZATO ==="
echo ""

# Verifica prerequisiti
log_info "Verifica prerequisiti..."
if ! command -v docker > /dev/null; then
    log_error "Docker non installato"
    exit 1
fi

if ! command -v docker-compose > /dev/null; then
    log_error "Docker Compose non installato"
    exit 1
fi

log_success "Prerequisiti verificati"

# Backup configurazione attuale
log_info "Backup configurazione attuale..."
if [ -f "docker-compose.yml" ]; then
    cp docker-compose.yml docker-compose.yml.backup
    log_success "Backup creato"
fi

# Build e avvio container
log_info "Build e avvio container..."
docker-compose down 2>/dev/null || true
docker-compose build --no-cache
docker-compose up -d

# Verifica container
log_info "Verifica container..."
sleep 10

if docker-compose ps | grep -q "Up"; then
    log_success "Container avviati"
else
    log_error "Errore nell'avvio container"
    docker-compose logs
    exit 1
fi

# Test servizi
log_info "Test servizi..."

# Test backend
if curl -f http://localhost:3001/health > /dev/null 2>&1; then
    log_success "Backend OK"
else
    log_warning "Backend non raggiungibile"
fi

# Test frontend
if curl -f http://localhost:3000 > /dev/null 2>&1; then
    log_success "Frontend OK"
else
    log_warning "Frontend non raggiungibile"
fi

# Test database
if docker exec gestionale_postgres pg_isready -U gestionale_user > /dev/null 2>&1; then
    log_success "Database OK"
else
    log_warning "Database non raggiungibile"
fi

echo ""
log_success "Deploy completato!"
echo ""
log_info "Comandi utili:"
log_info "  docker-compose ps          # Stato container"
log_info "  docker-compose logs        # Log container"
log_info "  docker-compose down        # Stop container"
log_info "  docker-compose up -d       # Riavvio container" 