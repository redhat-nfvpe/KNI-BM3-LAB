# this is our first build stage, it will not persist in the final image
FROM centos:7 as intermediate

# install git
RUN yum update
RUN yum install -y git

# add credentials on build
ARG SSH_PRIVATE_KEY
ADD ${SSH_PRIVATE_KEY} /root/.ssh/id_rsa
RUN chmod 600 /root/.ssh/id_rsa

# make sure your domain is accepted
RUN touch /root/.ssh/known_hosts
RUN ssh-keyscan github.com >> /root/.ssh/known_hosts

WORKDIR /root

RUN git clone git@github.com:redhat-nfvpe/kni-upi-lab.git
RUN ls


FROM centos:7

RUN yum install -y epel-release
RUN yum install -y jq python-pip
RUN yum install -y make
RUN pip install yq

# copy the repository form the previous image
COPY --from=intermediate /root/kni-upi-lab /root/kni-upi-lab
COPY install-config.yaml /root/kni-upi-lab/cluster

ENTRYPOINT [ "/bin/bash" ]
# ... actually use the repo :)
