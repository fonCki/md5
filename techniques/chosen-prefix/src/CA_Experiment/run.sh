if ! command -v openssl &> /dev/null
then
    echo "OpenSSL could not be found. Please install OpenSSL to proceed."
    exit 1
fi

# 1) Make one RSA private key (reused for both certs)
openssl genrsa -out key.pem 4096

# 2) Create cert A (self-signed) with subject A
openssl req -new -x509 -key key.pem -out certA.pem -days 3650 -sha256 \
  -subj "/CN=ACruelAttacker.com/O=Example Org/C=DK" \
  -set_serial 1

# 3) Create cert B (self-signed) with subject B (same key!)
openssl req -new -x509 -key key.pem -out certB.pem -days 3650 -sha256 \
  -subj "/CN=dtu.dk/O=Technical University of Denmark/C=DK" \
  -set_serial 2

