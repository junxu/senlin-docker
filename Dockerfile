FROM centos:latest
MAINTAINER BCEC (xujun@cmss.chinamobile.com)

LABEL senlin_version="2.0.2"


# Turns on MariaDB repos throughout the RPM build
COPY mariadb.yum.repo /etc/yum.repos.d/MariaDB.repo

RUN yum -y install http://repo.percona.com/release/7/RPMS/x86_64/percona-release-0.1-3.noarch.rpm

RUN rpm --import https://yum.mariadb.org/RPM-GPG-KEY-MariaDB \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-Percona


RUN curl http://trunk.rdoproject.org/centos7/current/delorean.repo -o /etc/yum.repos.d/delorean.repo

RUN curl http://trunk.rdoproject.org/centos7/delorean-deps.repo -o /etc/yum.repos.d/delorean-deps.repo


RUN rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7 \
    && yum install -y epel-release yum-plugin-priorities \
    && rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-EPEL-7 \
    && yum clean all
    

#### END REPO ENABLEMENT



RUN yum update -y \
    && yum clean all

# Pin package versions
RUN yum install -y \
        yum-plugin-versionlock \
    && yum clean all

# Update packages
RUN yum -y install \
        curl \
        python-kazoo \
        python-six \
        sudo \
        tar \
        which \
    && yum clean all


RUN yum -y install \
        git \
        iproute \
        mariadb-libs \
        MariaDB-shared \
        openssl \
    && yum clean all

RUN yum -y install \
        gcc \
        gcc-c++ \
        libffi-devel \
        libxml2-devel \
        libxslt-devel \
        mariadb-devel \
        openldap-devel \
        openssl-devel \
        postgresql \
        postgresql-devel \
        python-devel \
        sqlite-devel \
    && yum clean all

COPY sudoers /etc/sudoers
RUN chmod 440 /etc/sudoers \
    && chmod 440 /etc/sudoers \
    && mkdir -p /etc/senlin /var/log/senlin /var/cache/senlin \
    && useradd --user-group senlin \
    && chown -R senlin:senlin /etc/senlin /var/log/senlin /var/cache/senlin

RUN git clone --depth=1 https://github.com/openstack/requirements \
    && git clone -b xj-dev https://github.com/junxu/python-openstacksdk \
    && git clone -b xj-dev https://github.com/junxu/senlin

RUN curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py \
    && python get-pip.py \
    && rm get-pip.py \
    && pip --no-cache-dir install --upgrade -c requirements/upper-constraints.txt \
        jinja2 \
        kazoo \
        pymysql \
        python-memcached \
        six \ 
        MySQL-python \
    && pip --no-cache-dir install --upgrade -c requirements/upper-constraints.txt /senlin \
    && pip --no-cache-dir install /python-openstacksdk \
    && cp -r /senlin/etc/senlin/* /etc/senlin/ \ 
    && chown -R senlin:senlin /etc/senlin

COPY start.sh /bin/start.sh

RUN chmod 755 /bin/start.sh
