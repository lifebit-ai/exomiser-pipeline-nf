FROM zgmwum/exomiser

RUN apt-get update -y && \
    apt-get install -y \
    vim \
    unzip \
    nano \
    procps

RUN wget https://github.com/exomiser/Exomiser/releases/download/12.1.0/exomiser-cli-12.1.0-distribution.zip && \
	unzip exomiser-cli-12.1.0-distribution.zip && \
	rm exomiser-cli-12.1.0-distribution.zip && \
	mv /exomiser-cli-12.1.0 /exomiser

ADD run.py /usr/local/bin

# required for AWS-batch
COPY config /root/.aws/config
ENTRYPOINT []
