# Closetly

A local clothing recommendation app that combines your wardrobe, live weather, and today's plans.

## Run

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python app.py
```

Open http://127.0.0.1:5000.

The weather uses Open-Meteo and needs no API key. Add `OPENAI_API_KEY` before starting the app to enable vision-based clothing analysis; without it, photo uploads create an editable draft based on the filename.
