FROM python:3.12-alpine
WORKDIR /opt
COPY app.py releases.txt /opt/
RUN pip install --no-cache-dir flask
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "export ODOO_URL=\"${ODOO_URL:-$(awk 'NR==1 {print $2}' /opt/releases.txt)}\" && export PGADMIN_URL=\"${PGADMIN_URL:-$(awk 'NR==2 {print $2}' /opt/releases.txt)}\" && exec python /opt/app.py"]
