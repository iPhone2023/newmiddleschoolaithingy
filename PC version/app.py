from __future__ import annotations

import base64
import json
import os
import uuid
from datetime import date
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from flask import Flask, jsonify, render_template, request
from werkzeug.utils import secure_filename

BASE_DIR = Path(__file__).parent
DATA_FILE = BASE_DIR / "wardrobe.json"
UPLOAD_DIR = BASE_DIR / "static" / "uploads"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 8 * 1024 * 1024

SEED_ITEMS = [
    {"id": "seed-1", "name": "Cobalt overshirt", "category": "Layer", "color": "Cobalt", "warmth": 3, "waterproof": False, "image": None},
    {"id": "seed-2", "name": "Black straight-leg denim", "category": "Bottom", "color": "Black", "warmth": 4, "waterproof": False, "image": None},
    {"id": "seed-3", "name": "Ivory tee", "category": "Top", "color": "Ivory", "warmth": 1, "waterproof": False, "image": None},
    {"id": "seed-4", "name": "White leather sneakers", "category": "Shoes", "color": "White", "warmth": 1, "waterproof": False, "image": None},
]


def load_items() -> list[dict]:
    if not DATA_FILE.exists():
        return SEED_ITEMS.copy()
    try:
        return json.loads(DATA_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return SEED_ITEMS.copy()


def save_items(items: list[dict]) -> None:
    DATA_FILE.write_text(json.dumps(items, indent=2))


def fetch_json(url: str) -> dict:
    with urlopen(Request(url, headers={"User-Agent": "Closetly/1.0"}), timeout=8) as response:
        return json.loads(response.read())


def weather_for(city: str) -> dict:
    city = city.strip() or "New York"
    geo = fetch_json("https://geocoding-api.open-meteo.com/v1/search?" + urlencode({"name": city, "count": 1, "language": "en", "format": "json"}))
    place = (geo.get("results") or [{}])[0]
    if not place.get("latitude"):
        raise ValueError("We couldn't find that city.")
    forecast = fetch_json("https://api.open-meteo.com/v1/forecast?" + urlencode({"latitude": place["latitude"], "longitude": place["longitude"], "current": "temperature_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m", "temperature_unit": "fahrenheit", "wind_speed_unit": "mph", "timezone": "auto"}))
    current = forecast.get("current", {})
    return {"city": place.get("name", city), "temperature": round(current.get("temperature_2m", 68)), "feels_like": round(current.get("apparent_temperature", 68)), "precipitation": current.get("precipitation", 0), "wind": round(current.get("wind_speed_10m", 0)), "code": current.get("weather_code", 0)}


def generate_outfit(items: list[dict], weather: dict, event: str) -> dict:
    temp = weather["temperature"]
    needs_layer = temp < 65
    wet = weather["precipitation"] > 0
    ranked = sorted(items, key=lambda item: (item.get("waterproof", False) == wet, item.get("warmth", 2)), reverse=True)
    tops = [item for item in ranked if item["category"] in ("Top", "Layer")]
    bottoms = [item for item in ranked if item["category"] == "Bottom"]
    shoes = [item for item in ranked if item["category"] == "Shoes"]
    selected = tops[:2] if needs_layer and len(tops) > 1 else tops[:1]
    selected += bottoms[:1] + shoes[:1]
    if not selected:
        selected = items[:3]
    names = [item["name"] for item in selected]
    if wet:
        note = "Rain is in the mix, so prioritize your most weather-ready pieces."
    elif temp < 55:
        note = "A colder day calls for a grounded base and one reliable layer."
    elif temp > 78:
        note = "Keep it breathable today and let the accessories do the work."
    else:
        note = "A balanced base keeps this look comfortable from morning to evening."
    if event:
        note += f" It fits the tone of your {event.lower()} today."
    return {"items": selected, "title": "The considered everyday look", "note": note, "why": [f"{weather['temperature']}°F with a {weather['feels_like']}°F feel", "Built from your available wardrobe", event or "Easy enough for a flexible day"]}


@app.get("/")
def index():
    return render_template("index.html", items=load_items(), today=date.today().isoformat())


@app.get("/api/weather")
def api_weather():
    try:
        return jsonify(weather_for(request.args.get("city", "New York")))
    except Exception as error:
        return jsonify({"error": str(error)}), 400


@app.post("/api/items")
def add_item():
    item = request.form.to_dict()
    photo = request.files.get("photo")
    if not item.get("name"):
        return jsonify({"error": "Give this piece a name."}), 400
    image_path = None
    if photo and photo.filename:
        extension = Path(secure_filename(photo.filename)).suffix.lower() or ".jpg"
        filename = f"{uuid.uuid4().hex}{extension}"
        photo.save(UPLOAD_DIR / filename)
        image_path = f"/static/uploads/{filename}"
    created = {"id": uuid.uuid4().hex, "name": item["name"], "category": item.get("category", "Top"), "color": item.get("color", "Neutral"), "warmth": int(item.get("warmth", 2)), "waterproof": item.get("waterproof") == "on", "image": image_path}
    items = load_items()
    items.insert(0, created)
    save_items(items)
    return jsonify(created)


@app.delete("/api/items/<item_id>")
def delete_item(item_id: str):
    save_items([item for item in load_items() if item["id"] != item_id])
    return jsonify({"ok": True})


@app.post("/api/recommend")
def recommend():
    payload = request.get_json() or {}
    weather = payload.get("weather")
    if not weather:
        return jsonify({"error": "Load the weather first."}), 400
    result = generate_outfit(load_items(), weather, payload.get("event", ""))
    return jsonify(result)


@app.post("/api/analyze-photo")
def analyze_photo():
    photo = request.files.get("photo")
    if not photo:
        return jsonify({"error": "No photo received."}), 400
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        return jsonify({"name": Path(photo.filename).stem.replace("_", " ").title(), "category": "Top", "color": "Neutral", "warmth": 2, "message": "Added a quick draft. You can edit the details before saving."})
    raw = base64.b64encode(photo.read()).decode()
    body = {"model": "gpt-4o-mini", "response_format": {"type": "json_object"}, "messages": [{"role": "user", "content": [{"type": "text", "text": "Identify this clothing item. Return JSON with name, category (Top, Bottom, Layer, Shoes, Accessory), color, warmth (1-5), waterproof (true/false)."}, {"type": "image_url", "image_url": {"url": f"data:{photo.mimetype};base64,{raw}"}}]}]}
    req = Request("https://api.openai.com/v1/chat/completions", data=json.dumps(body).encode(), headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}, method="POST")
    try:
        with urlopen(req, timeout=30) as response:
            content = json.loads(response.read())["choices"][0]["message"]["content"]
        return jsonify(json.loads(content))
    except Exception as error:
        return jsonify({"error": f"Photo analysis failed: {error}"}), 502


if __name__ == "__main__":
    app.run(debug=True, port=int(os.getenv("PORT", "5000")))
