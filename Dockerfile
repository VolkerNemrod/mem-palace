FROM python:3.12-slim

# curl jest potrzebny tylko do HEALTHCHECK w docker-compose.yml
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# 3.5.0 to pierwsza wersja z opt-in transportem HTTP (--transport http).
# 3.4.1 (poprzedni pin) tej flagi jeszcze nie mial - stad wczesniejszy blad
# po probie przelaczenia na "wersje www".
RUN pip install --no-cache-dir mempalace==3.5.0

WORKDIR /palace

# UWAGA: "mempalace init" tu NIE jest potrzebne i bylo blednie wywolywane
# (bez --palace, wiec pisalo do domyslnej sciezki ~/.mempalace w kontenerze,
# a nie do zamontowanego /palace - i tak by sie gubilo przy kazdym restarcie).
# mempalace-mcp sam tworzy strukture palace (mempalace.yaml, chroma.sqlite3)
# przy pierwszym starcie, jesli katalog /palace jest pusty - init nie jest
# do tego wymagane.
CMD ["mempalace-mcp", "--palace", "/palace", "--transport", "http", "--host", "0.0.0.0", "--port", "8000"]
