import os
from flask import Flask, render_template_string

app = Flask(__name__)

TEMPLATE = """<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Legeni Academy - IC GROUP</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; background: #f5f7fa; text-align: center; }
        header { background: #1a365d; color: white; padding: 2rem; }
        .cards { display: flex; justify-content: center; gap: 2rem; margin: 3rem auto; max-width: 800px; }
        .card { background: white; padding: 2rem; border-radius: 8px; box-shadow: 0 2px 8px rgba(0,0,0,0.1); width: 300px; }
        a.btn { display: inline-block; margin-top: 1rem; padding: 0.75rem 1.5rem; background: #2b6cb0; color: white; text-decoration: none; border-radius: 4px; }
    </style>
</head>
<body>
    <header>
        <h1>Bienvenue sur Legeni Academy (IC GROUP)</h1>
        <p>Portail d'accès aux applications internes</p>
    </header>
    <div class="cards">
        <div class="card">
            <h2>ERP & LMS Odoo</h2>
            <p>Gestion d'entreprise et plateforme e-Learning interne.</p>
            <a class="btn" href="{{ odoo_url }}">Accéder à Odoo</a>
        </div>
        <div class="card">
            <h2>Administration pgAdmin 4</h2>
            <p>Administration graphique de la base PostgreSQL.</p>
            <a class="btn" href="{{ pgadmin_url }}">Accéder à pgAdmin</a>
        </div>
    </div>
</body>
</html>
"""

@app.route("/")
def index():
    return render_template_string(
        TEMPLATE,
        odoo_url=os.environ.get("ODOO_URL", "https://www.odoo.com"),
        pgadmin_url=os.environ.get("PGADMIN_URL", "https://www.pgadmin.org"),
    )

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
