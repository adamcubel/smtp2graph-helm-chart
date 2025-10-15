#!/bin/bash

# CA-Signed Certificate Generation Script
# This script creates a Certificate Authority and generates CA-signed certificates

set -e

# Configuration variables
CA_DIR="./ca"
CERTS_DIR="./certs"
CA_KEY="${CA_DIR}/ca-key.pem"
CA_CERT="${CA_DIR}/ca-cert.pem"
CA_DAYS=3650  # CA valid for 10 years
CERT_DAYS=365 # Server cert valid for 1 year

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to create directory structure
setup_directories() {
    print_info "Setting up directory structure..."
    mkdir -p "${CA_DIR}"
    mkdir -p "${CERTS_DIR}"
}

# Function to create CA
create_ca() {
    if [[ -f "${CA_CERT}" ]]; then
        print_warn "CA certificate already exists at ${CA_CERT}"
        read -p "Do you want to recreate it? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Using existing CA certificate"
            return
        fi
    fi

    print_info "Creating Certificate Authority..."

    # Generate CA private key
    openssl genrsa -out "${CA_KEY}" 4096

    # Create CA configuration file with certificate signing extensions
    local CA_CONFIG="${CA_DIR}/ca.cnf"
    cat > "${CA_CONFIG}" << EOF
[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_ca

[req_distinguished_name]

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
EOF

    # Generate CA certificate with certificate signing enabled
    openssl req -new -x509 -days "${CA_DAYS}" -key "${CA_KEY}" \
        -out "${CA_CERT}" \
        -config "${CA_CONFIG}" \
        -subj "/C=US/ST=State/L=City/O=MyOrganization/OU=IT/CN=My CA"

    rm -f "${CA_CONFIG}"

    print_info "CA certificate created successfully!"
    print_info "CA Certificate: ${CA_CERT}"
    print_info "CA Private Key: ${CA_KEY}"
}

# Function to create a server certificate
create_server_cert() {
    local DOMAIN=$1

    if [[ -z "${DOMAIN}" ]]; then
        print_error "Domain name is required"
        return 1
    fi

    print_info "Generating certificate for ${DOMAIN}..."

    local SERVER_KEY="${CERTS_DIR}/${DOMAIN}-key.pem"
    local SERVER_CSR="${CERTS_DIR}/${DOMAIN}-csr.pem"
    local SERVER_CERT="${CERTS_DIR}/${DOMAIN}-cert.pem"
    local EXT_FILE="${CERTS_DIR}/${DOMAIN}-ext.cnf"

    # Generate server private key
    openssl genrsa -out "${SERVER_KEY}" 2048

    # Generate Certificate Signing Request (CSR)
    openssl req -new -key "${SERVER_KEY}" \
        -out "${SERVER_CSR}" \
        -subj "/C=US/ST=State/L=City/O=MyOrganization/OU=IT/CN=${DOMAIN}"

    # Create extensions file for SAN (Subject Alternative Names) and Extended Key Usage
    cat > "${EXT_FILE}" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth, codeSigning, emailProtection, timeStamping
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${DOMAIN}
EOF

    # Sign the certificate with CA
    openssl x509 -req -in "${SERVER_CSR}" \
        -CA "${CA_CERT}" -CAkey "${CA_KEY}" \
        -CAcreateserial \
        -out "${SERVER_CERT}" \
        -days "${CERT_DAYS}" \
        -extfile "${EXT_FILE}"

    # Clean up CSR and extensions file
    rm -f "${SERVER_CSR}" "${EXT_FILE}"

    print_info "Certificate generated successfully!"
    print_info "Certificate: ${SERVER_CERT}"
    print_info "Private Key: ${SERVER_KEY}"

    # Verify the certificate
    print_info "Verifying certificate..."
    openssl verify -CAfile "${CA_CERT}" "${SERVER_CERT}"
}

# Function to display certificate info
show_cert_info() {
    local CERT_FILE=$1

    if [[ ! -f "${CERT_FILE}" ]]; then
        print_error "Certificate file not found: ${CERT_FILE}"
        return 1
    fi

    print_info "Certificate details for ${CERT_FILE}:"
    openssl x509 -in "${CERT_FILE}" -text -noout
}

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -c, --create-ca              Create a new Certificate Authority
    -s, --sign DOMAIN            Generate and sign a certificate for DOMAIN
    -i, --info CERT_FILE         Display information about a certificate
    -h, --help                   Show this help message

Examples:
    $0 --create-ca                    # Create a new CA
    $0 --sign example.com             # Generate cert for example.com
    $0 --sign "*.example.com"         # Generate wildcard cert
    $0 --info certs/example.com-cert.pem  # Show cert details

EOF
}

# Main script logic
main() {
    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    setup_directories

    while [[ $# -gt 0 ]]; do
        case $1 in
            -c|--create-ca)
                create_ca
                shift
                ;;
            -s|--sign)
                if [[ -z "$2" ]]; then
                    print_error "Domain name required for --sign option"
                    exit 1
                fi
                if [[ ! -f "${CA_CERT}" ]]; then
                    print_error "CA certificate not found. Create CA first with --create-ca"
                    exit 1
                fi
                create_server_cert "$2"
                shift 2
                ;;
            -i|--info)
                if [[ -z "$2" ]]; then
                    print_error "Certificate file required for --info option"
                    exit 1
                fi
                show_cert_info "$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

main "$@"

# Usage:
# cert-create.sh --create-ca
# cert-create.sh --sign mail.cubel.test
