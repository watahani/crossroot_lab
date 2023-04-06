# How to create Cross Root Certificate with CRL endpoint

```mermaid
flowchart TB
    subgraph four-tiers
    Root_CA_1-->ROOT_CA_2'
    ROOT_CA_2'-->INTERMEDIATE_CA
    subgraph three-tiers
    INTERMEDIATE_CA-->SERVER_CERT
    ROOT_CA_2-->INTERMEDIATE_CA
    end
    end
    ROOT_CA_2-. Same Private Key .-ROOT_CA_2'
```

## Requirements

- openssl 3.0.x
- PowerShell 5.x
- Web server that stores the CRL (I use Azure Blob with Force Encryption set to False)

## Create Root two CAs

```powershell
$configPath = Join-Path -Path $(Get-Location) -ChildPath openssl.cnf
$env:OPENSSL_CONF = $configPath

$ENV:ALT_NAME = "altname.example.com"
$CRL_FOR_ROOT_CA_1 = "http://your-host/root_ca_1.crl"
$CRL_FOR_ROOT_CA_2 = "http://your-host/root_ca_2.crl"
```

```powershell
$CaList = "root_ca_1","root_ca_2","intermediate_ca"
$CaList | %{ New-Item -Type Directory "$_\ca" }
```

```sh
$CaList | %{
    cd "$_\ca"
    New-Item -Type Directory "certs", "crl","newcerts","private"
    Write-Output 0001 | Out-File -encoding UTF8 -PSPath serial -NoNewLine
    Write-Output "" | Out-File -encoding UTF8 -PSPath index.txt -NoNewLine
    Write-Output 0001 | Out-File -encoding UTF8 -PSPath crlnumber -NoNewLine
    cd ../../
}
```

```sh
openssl genrsa -out ./root_ca_1/ca/private/ca.key.pem 2048
openssl req -reqexts v3_req -new -key ./root_ca_1/ca/private/ca.key.pem -x509 -nodes -days 3650 -out ./root_ca_1/ca/certs/ca.crt.pem -subj "/C=JP/ST=Tokyo/L=Shinagawa/O=Contoso/OU=CA/CN=ROOT_CA_1"

openssl genrsa -out ./root_ca_2/ca/private/ca.key.pem 2048
openssl req -reqexts v3_req -new -key ./root_ca_2/ca/private/ca.key.pem -x509 -nodes -days 3650 -out ./root_ca_2/ca/certs/self.ca.crt.pem -subj "/C=JP/ST=Tokyo/L=Shinagawa/O=Contoso/OU=CA/CN=ROOT_CA_2"
```


## Create Intermediate CA (Same Private Key as ROOT_CA_2)

```sh
openssl req -new -key ./root_ca_2/ca/private/ca.key.pem -out ./root_ca_2/ca/certs/cert.req -subj "/C=JP/ST=Tokyo/L=Shinagawa/O=Contoso/OU=CA/CN=ROOT_CA_2"
```

Signed with ROOT_CA_1

```sh
$env:CRL_URL="http://cawahaniyacom.blob.core.windows.net/crl/crossrootlab_root_ca_1.crl"
cd root_ca_1
openssl ca  -extensions v3_ca_with_crl -in ../root_ca_2/ca/certs/cert.req -days 3650 -out ../root_ca_2/ca/certs/ca.crt.pem
cd ..
```

Then ROOT_CA_1 ca behave as Intermediate CA.

## Create Intermediate CA

```powershell
openssl genrsa -out ./intermediate_ca/ca/private/ca.key.pem 2048
openssl req -new -key ./intermediate_ca/ca/private/ca.key.pem -out ./intermediate_ca/ca/certs/cert.req -subj "/C=JP/ST=Tokyo/L=Shinagawa/O=Contoso/OU=CA/CN=INTERMEDIATE_CA"
```

Signed with ROOT_CA_2

```sh
$env:CRL_URL=$CRL_FOR_ROOT_CA_2
cd root_ca_2
openssl ca -extensions v3_ca_with_crl -in ../intermediate_ca/ca/certs/cert.req -days 3650 -out ../intermediate_ca/ca/certs/ca.crt.pem
cd ../
```

Then root CA2 can behave as intermediate CA.

## Create Server Certificate

```conf
[ v3_server_req ]
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

subjectAltName = @alt_names

# CRL is not needed in my environment
# crlDistributionPoints = URI:$ENV::CRL_URL

[ alt_names ]
DNS.1 = $ENV::ALT_NAME
```

```powershell
cd intermediate_ca
openssl genrsa -out ./server.key 2048
openssl req  -new -extensions v3_server_req -key ./server.key -out server.csr -subj "/C=JP/ST=Tokyo/L=Shinagawa/O=Contoso/OU=CA/CN=$($env:ALT_NAME)"
openssl ca -extensions  v3_server_req -in ./server.csr -days 365 -out ./server.cer
cd ..
```

## Create PFX

```powershell
$ServerCert = Get-Content .\intermediate_ca\server.cer
$IntermediateCert = Get-Content .\intermediate_ca\ca\certs\ca.crt.pem
$RootCA2CertSignedByRootCA1 = Get-Content .\root_ca_2\ca\certs\ca.crt.pem
$RootCA1Cert = Get-Content .\root_ca_1\ca\certs\ca.crt.pem
$CertChain = $ServerCert + $IntermediateCert + $RootCA2CertSignedByRootCA1 + $RootCA1Cert
$CertChain | Out-File -Encoding UTF8 -Path ./certchain.cer

$RootCA1Cert | Out-File -Encoding UTF8 -Path ./ROOT_CA_1.cer
$RootCA2Cert = Get-Content .\root_ca_1\ca\certs\self.ca.crt.pem
$RootCA2Cert | Out-File -Encoding UTF8 -Path ./ROOT_CA_2.cer

openssl pkcs12 -export -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -nomac -out ./server.pfx  -inkey ./intermediate_ca/server.key -in ./certchain.cer -nodes
```

## Revoke Intermediate Certificate

```sh
# revoke root ca 2
cd root_ca_1
openssl ca -revoke .\ca\newcerts\01.pem
openssl ca  -gencrl -crldays 1 -out ../output/crossrootlab_root_ca_1.crl
cd ..

cd root_ca_2
openssl ca -gencrl -crldays 1 -out ../output/crossrootlab_root_ca_2.crl
cd ..
```
