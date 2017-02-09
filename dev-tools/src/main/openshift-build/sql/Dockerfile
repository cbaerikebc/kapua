FROM RHEL:RHEL7

RUN INSTALL_PKGS="java-1.8.0-openjdk java-1.8.0-openjdk-devel atomic-openshift-clients" && \
    yum install -y $INSTALL_PKGS && \
    rpm -V $INSTALL_PKGS && \
    yum clean all && \

ENV DATA_DIR /opt/h2-data

RUN curl http://www.h2database.com/h2-2016-10-31.zip -o h2-2016-10-31.zip
RUN unzip h2-2016-10-31.zip -d /opt/
RUN rm h2-2016-10-31.zip
RUN mkdir -p ${DATA_DIR}

VOLUME ${DATA_DIR}

EXPOSE 8181 3306

CMD java -cp /opt/h2/bin/h2*.jar org.h2.tools.Server \
  -web -webAllowOthers -webPort 8181 -tcp -tcpAllowOthers -tcpPort 3306 \
  -baseDir ${DATA_DIR}
