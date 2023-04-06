switch ($PSEdition) {
    "Desktop" { 
        Function Out-FileWithUTF8 {
            param(
                [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
                [string]$Content,
                [Parameter(Mandatory=$true)]
                [string]$Path
            )
            $Content | %{[Text.Encoding]::UTF8.GetBytes($_)} | Set-Content -Encoding Byte -Path $Path
        }
     }
    "Core" {
        Function Out-FileWithUTF8 {
            param(
                [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
                [string]$Content,
                [Parameter(Mandatory=$true)]
                [string]$Path
            )
            $Content | Out-File -Encoding utf8 -FilePath $Path -NoNewline
        }
    }
}

$CRL_FOR_ROOT_CA_1 = "http://your-host/root_ca_1.crl"
$CRL_FOR_ROOT_CA_2 = "http://your-host/root_ca_2.crl"

$ENV:ALT_NAME = "altname.example.com"
$env:CRL_URL = $CRL_FOR_ROOT_CA_1

$configPath = Join-Path -Path $(Get-Location) -ChildPath openssl.cnf
$env:OPENSSL_CONF = $configPath

# create ca folders and files
$CaList = "root_ca_1","root_ca_2","intermediate_ca"
$CaList | %{ New-Item -Type Directory "$_\ca" }

$CaList | %{
    cd "$_\ca"
    New-Item -Type Directory "certs", "crl","newcerts","private"
    "0001" | Out-String | Out-FileWithUTF8 -Path serial
    New-Item -Type File -Path index.txt
    "0001" | Out-String | Out-FileWithUTF8 -Path crlnumber
    cd ../../
}

# create root CAs
openssl genrsa -out ./root_ca_1/ca/private/ca.key.pem 2048
openssl req -reqexts v3_req -new -key ./root_ca_1/ca/private/ca.key.pem -x509 -nodes -days 3650 -out ./root_ca_1/ca/certs/ca.crt.pem -subj "/C=JP/ST=Tokyo/L=Shinagawa/O=Contoso/OU=CA/CN=ROOT_CA_1"

openssl genrsa -out ./root_ca_2/ca/private/ca.key.pem 2048
openssl req -reqexts v3_req -new -key ./root_ca_2/ca/private/ca.key.pem -x509 -nodes -days 3650 -out ./root_ca_2/ca/certs/self.ca.crt.pem -subj "/C=JP/ST=Tokyo/L=Shinagawa/O=Contoso/OU=CA/CN=ROOT_CA_2"

# sign root CA2 with root CA1
openssl req -new -reqexts v3_req -key ./root_ca_2/ca/private/ca.key.pem -out ./root_ca_2/ca/certs/cert.req -subj "/C=JP/ST=Tokyo/L=Shinagawa/O=Contoso/OU=CA/CN=ROOT_CA_2"
$env:CRL_URL=$CRL_FOR_ROOT_CA_1
cd root_ca_1
openssl ca -batch -extensions v3_ca_with_crl -in ../root_ca_2/ca/certs/cert.req -days 3650 -out ../root_ca_2/ca/certs/ca.crt.pem
cd ..

# create intermediate CA
openssl genrsa -out ./intermediate_ca/ca/private/ca.key.pem 2048
openssl req -new -key ./intermediate_ca/ca/private/ca.key.pem -out ./intermediate_ca/ca/certs/cert.req -subj "/C=JP/ST=Tokyo/L=Shinagawa/O=Contoso/OU=CA/CN=INTERMEDIATE_CA"

# signed with root CA2
$env:CRL_URL=$CRL_FOR_ROOT_CA_2
cd root_ca_2
openssl ca -batch -extensions v3_ca_with_crl -in ../intermediate_ca/ca/certs/cert.req -days 3650 -out ../intermediate_ca/ca/certs/ca.crt.pem
cd ../

# create server certificate CA
cd intermediate_ca
openssl genrsa -out ./server.key 2048
openssl req  -new -extensions v3_server_req -key ./server.key -out server.csr -subj "/C=JP/ST=Tokyo/L=Shinagawa/O=Contoso/OU=CA/CN=$($env:ALT_NAME)"
openssl ca -batch -extensions  v3_server_req -in ./server.csr -days 365 -out ./server.cer
cd ../

New-Item -Type Directory "output"

$ServerCert = Get-Content .\intermediate_ca\server.cer
$IntermediateCert = Get-Content .\intermediate_ca\ca\certs\ca.crt.pem
$RootCA2CertSignedByRootCA1 = Get-Content .\root_ca_2\ca\certs\ca.crt.pem
$RootCA1Cert = Get-Content .\root_ca_1\ca\certs\ca.crt.pem
$CertChain = $ServerCert + $IntermediateCert + $RootCA2CertSignedByRootCA1 + $RootCA1Cert
$CertChain | Out-String | Out-FileWithUTF8 -Path ./output/certchain.cer

$RootCA1Cert | Out-String | Out-FileWithUTF8 -Path./output/ROOT_CA_1.cer
$RootCA2Cert = Get-Content .\root_ca_2\ca\certs\self.ca.crt.pem
$RootCA2Cert | Out-String | Out-FileWithUTF8 -Path ./output/ROOT_CA_2.cer
$RootCA2CertSignedByRootCA1 | Out-String | Out-FileWithUTF8 -Path ./output/ROOT_CA_2_singed_by_CA1.cer

openssl pkcs12 -export -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -nomac -out ./output/server.pfx  -inkey ./intermediate_ca/server.key -in ./output/certchain.cer -passout pass:

