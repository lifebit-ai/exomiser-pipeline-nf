FROM continuumio/miniconda3@sha256:77f9119def83d94b7afb654b39a1c21aaa7f255518aba57de08321760c27c86a

ENV VERSION="1.6.6-py_2"

ARG ENV_NAME="ped-parser"

LABEL description="Docker containing the ped_parser python package." \
    software.version="${VERSION}" \
    maintainer="Leila Mansouri: leila.mansouri@lifebit.ai" \
    name="quay.io/lifebitaiorg/ped_parser:1.6.6-py_2"

#needed as per the documentation
RUN apt-get update -y &&\
    apt-get install -y procps \
    zlib1g &&\
    rm -rf /var/lib/apt/lists/*

#installing the tool and its dependencies
RUN pip install ped_parser

RUN pip install pandas

ENTRYPOINT [ ]
