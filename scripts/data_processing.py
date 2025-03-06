import os
import json
import pandas as pd

# Funktion zum Extrahieren von Kartenwert und Position aus einer Kartenbeschreibung
def extract_card_data(card_str):
    if card_str is None or "Card: None" in card_str:
        return None, None  # Wenn der Kartenwert None ist oder ungültige Karte, gebe None zurück
    
    try:
        # Teilen des Kartenwerts und der Position
        card_value, pos_str = card_str.split(" , Position:")
        card_value = int(card_value.split(": ")[1])  # Umwandlung des Kartenwerts in eine Zahl
        pos_str = pos_str.strip("()")
        row, col = map(int, pos_str.split(", "))  # Umwandlung der Position in Zeile und Spalte (r, c)
        return card_value, (row, col)
    except Exception as e:
        return None, None  # Rückgabe von None, wenn ein Fehler auftritt

# Funktion zur Verarbeitung der Spiel-Daten aus JSON-Dateien
def transform_game_data_from_json_files(directory):
    transformed_data = []

    # Alle JSON-Dateien im angegebenen Verzeichnis einlesen
    for filename in os.listdir(directory):
        if filename.endswith(".json"):  # Wir verarbeiten nur JSON-Dateien
            file_path = os.path.join(directory, filename)
            with open(file_path, 'r', encoding="utf-8") as file:
                data = json.load(file)
                
                # Jede Spielrunde in den JSON-Daten verarbeiten
                for game in data:
                    flipped_cards = [extract_card_data(card) for card in game.get('Flipped Cards', [])]
                    covered_cards = [extract_card_data(card) for card in game.get('Covered Cards', [])]
                    selectable_cards = [extract_card_data(card) for card in game.get('Selectable Cards', [])]
                    
                    # Feature: Anzahl der aufgedeckten Karten
                    num_flipped = len([card for card in flipped_cards if card[0] is not None])
                    num_covered = len([card for card in covered_cards if card[0] is not None])
                    num_selectable = len([card for card in selectable_cards if card[0] is not None])
                    
                    # Letzte aufgedeckte Karte
                    last_flipped_card_value, last_flipped_card_pos = extract_card_data(game.get('Last Flipped Card'))
                    if last_flipped_card_value is None:
                        last_flipped_card_value = 0  # Setze einen Default-Wert
                        last_flipped_card_pos = (0, 0)  

                    # Last Guess & Guess speichern
                    last_guess = game.get("Last Guess", "Unknown")  # Falls nicht vorhanden, "Unknown"
                    guess = game.get("Guess", None)  # Falls nicht vorhanden, None
                    try:
                        guess = int(guess)  # Versuche, Guess in Integer umzuwandeln
                    except (ValueError, TypeError):
                        guess = None  # Falls das nicht geht, bleibt es None

                    # Zeitstempel umwandeln
                    timestamp = game.get('Timestamp', '1970-01-01_00-00')
                    timestamp = timestamp.replace("_", " ")  # Formatierung anpassen
                    timestamp = pd.to_datetime(timestamp, format='%Y-%m-%d %H-%M', errors='coerce')  
                    timestamp_seconds = (timestamp - pd.Timestamp("1970-01-01")) // pd.Timedelta("1s")

                    # Alle Features in ein Dictionary speichern
                    transformed_data.append({
                        'Timestamp': timestamp_seconds,
                        'Turn': game.get('Turn', 0),
                        'Num Flipped Cards': num_flipped,
                        'Num Covered Cards': num_covered,
                        'Num Selectable Cards': num_selectable,
                        'Last Flipped Card Value': last_flipped_card_value,
                        'Last Flipped Card Position': last_flipped_card_pos,
                        'Last Guess': last_guess,
                        'Guess': guess
                    })
    
    # Erstellen des DataFrames mit den gesammelten Daten
    return pd.DataFrame(transformed_data)

# Verzeichnis mit den JSON-Dateien (ersetze diesen Pfad durch dein tatsächliches Verzeichnis)
directory = 'json_files'  # Falls nötig, hier den Pfad ändern

# Verarbeite alle JSON-Dateien im Verzeichnis und erstelle das DataFrame
df = transform_game_data_from_json_files(directory)

# Falls du nur sinnvolle Daten haben willst, filtere ungültige Zeilen
df = df[df['Last Flipped Card Position'] != (0, 0)]

# Zeige das DataFrame an
print(df)
