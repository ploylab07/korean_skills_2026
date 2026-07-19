FROM public.ecr.aws/amazonlinux/amazonlinux:2023-minimal
RUN dnf install -y curl-minimal && dnf clean all
COPY set-hostname.sh /set-hostname.sh
RUN chmod +x /set-hostname.sh
ENTRYPOINT ["/set-hostname.sh"]
