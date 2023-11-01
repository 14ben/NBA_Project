FROM ubuntu:20.04

RUN apt update
RUN apt install -y wget unzip
RUN apt install -y curl 

# Download the latest version of Terraform from the official website
ADD https://releases.hashicorp.com/terraform/1.4.7/terraform_1.4.7_linux_amd64.zip .

# Unzip the downloaded file:
RUN unzip terraform_1.4.7_linux_amd64.zip

# Move the terraform binary to a directory in your system's PATH...
RUN mv terraform /usr/local/bin/

WORKDIR /provision

COPY full_pro.sh /provision/
COPY select.sh /provision/
COPY destroy.sh /provision/
COPY partial.sh /provision/

RUN chmod +x /provision/full_pro.sh
RUN chmod +x /provision/select.sh
RUN chmod +x /provision/partial.sh
