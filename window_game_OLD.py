import tkinter as tk
import random
import pandas as pd

# Kartensymbole und Werte - Jede Karte kommt 4-mal vor
kartenwerte = ['6','6', '6','6', '7','7', '7','7','8','8','8','8', '9','9','9','9', 
               '10','10','10','10', 'Unter','Unter','Unter','Unter', 'Ober','Ober','Ober','Ober', 
               'König','König','König','König', 'Ass', 'Ass', 'Ass', 'Ass']

# Layout der Karten auf dem Tisch (mit '0' für offene Karten, 'X' für verdeckte Karten, und ' ' für leere Felder)
layout = [
    ['0', 'X', 'X', 'X', '0'],
    ['X', ' ', 'X', ' ', 'X'],
    ['X', 'X', 'X', 'X', 'X', '0'],
    ['X', ' ', 'X', ' ', 'X'],
    ['0', 'X', 'X', 'X', '0']
]

# Funktion, um das Kartendeck zufällig auf den Feldern anzuordnen und zu decken
def erstelle_deck_layout():
    karten_index = 0
    deck_data = []
    
    # Zuerst Karten aus dem Deck entfernen, die in den '0'-Feldern aufgedeckt sind
    offene_karten = []

    for row in range(len(layout)):
        for col in range(len(layout[row])):
            cell = layout[row][col]
            if cell == '0':  # Offene Karten (0) - Diese Karten sind bereits aufgedeckt
                offene_karten.append(kartenwerte[karten_index])
                karten_index += 1

    # Entferne diese Karten aus dem Deck
    for karte in offene_karten:
        kartenwerte.remove(karte)

    # Danach alle Karten dem Layout zuweisen
    for row in range(len(layout)):
        for col in range(len(layout[row])):
            cell = layout[row][col]
            if cell == '0':  # Offene Karten (0)
                kartenwert = offene_karten.pop(0)  # Diese Karten sind bereits aufgedeckt
            elif cell == 'X':  # Verdeckte Karten (X)
                kartenwert = None  # None bedeutet, dass die Karte verdeckt ist
            else:
                continue

            deck_data.append({"row": row, "col": col, "card": kartenwert})

    # DataFrame aus der Liste von Dictionaries erstellen
    return pd.DataFrame(deck_data)

# Das Decklayout als DataFrame erstellen
deck_df = erstelle_deck_layout()

# Funktion zum Überprüfen der Nachbarn im rechten Winkel oder gegenüber
def nachbarn_im_rechten_winkel_oder_gegenüber(gefundene_nachbarn, layout, deck_df):

    print("hier")

    if len(gefundene_nachbarn) != 3:
        return False, "Kein Treffer"  # Rückgabe, falls nicht genau 3 Nachbarn gefunden werden
    
    # Überprüfe, ob die Nachbarn im rechten Winkel oder gegenüberstehen
    (r1, c1), (r2, c2), (r3, c3) = gefundene_nachbarn
    
    # Funktion zum Umkehren (Aufdecken) der Karte
    def umdrehen_und_aufdecken(r, c):
        index = (deck_df['row'] == r) & (deck_df['col'] == c)
        if index.any():
            card = deck_df.loc[index, 'card'].values[0]
            if card is None:  # Karte ist noch verdeckt
                neue_karte = kartenwerte.pop(0)  # Nehme eine Karte aus dem Deck
                deck_df.loc[index, 'card'] = neue_karte  # Decke die Karte auf

                # Aktualisiere die GUI (diese Funktion muss entsprechend definiert werden)
                update_gui()

    # Zuerst decken wir alle Nachbarn auf, falls sie verdeckt sind
    umdrehen_und_aufdecken(r1, c1)
    umdrehen_und_aufdecken(r2, c2)
    umdrehen_und_aufdecken(r3, c3)

    # Fall: Gegenüber - wenn zwei Nachbarn auf derselben vertikalen oder horizontalen Linie stehen
    if (r1 == r2 and c1 != c2 and r3 == r2) or (c1 == c2 and r1 != r2 and c3 == c2):
        return True, "Gegenüber"  # Wenn sie gegenüberliegen

    # Fall: Rechter Winkel - wenn zwei Nachbarn in einem 90-Grad-Winkel stehen
    if (r1 == r2 and c2 == c3) or (c1 == c2 and r2 == r3):
        return True, "Rechter Winkel"  # Wenn sie im rechten Winkel stehen

    return False, "Kein Treffer"  # Wenn weder im rechten Winkel noch gegenüber



# Funktion zum Überprüfen der Nachbarn und offenen Nachbarn eines bestimmten Feldes
def nachbarn_und_offene_nachbarn(row, col):
    # Definiere die 4 benachbarten Felder (oben, unten, links, rechts)
    nachbarn = [
        (row-1, col),  # Oben
        (row+1, col),  # Unten
        (row, col-1),  # Links
        (row, col+1)   # Rechts
    ]
    
    alle_nachbarn = []  # Liste für alle Nachbarn
    offene_nachbarn = []  # Liste für die offenen Nachbarn

    # Liste der Felder, die nicht als Nachbarn gezählt werden sollen
    ausgeschlossene_felder = [(1, 1), (3, 1), (3, 3), (1, 3)]

    # Alle Nachbarn sammeln (egal ob verdeckt oder aufgedeckt)
    for r, c in nachbarn:
        # Sicherstellen, dass das Nachbarfeld innerhalb des Layouts liegt
        if 0 <= r < len(layout) and 0 <= c < len(layout[r]):

            # Bedingung hinzufügen, um bestimmte Felder zu ignorieren
            if (r, c) in ausgeschlossene_felder:
                continue  # Wenn das Feld in der Liste der ausgeschlossenen Felder ist, überspringe es

            alle_nachbarn.append((r, c))  # Füge den Nachbarn hinzu

            # Überprüfe, ob der Nachbar aufgedeckt ist
            index = (deck_df['row'] == r) & (deck_df['col'] == c)
            if index.any():  # Überprüfen, ob der Index existiert
                nachbar_karte = deck_df.loc[index, 'card'].values[0]
                if nachbar_karte is not None:  # Nur wenn der Nachbar aufgedeckt ist
                    offene_nachbarn.append((r, c))  # Füge nur die offenen Nachbarn hinzu

    # Gib beide Listen zurück
    return alle_nachbarn, offene_nachbarn


# Beispiel: Durchlaufe das gesamte Layout und gebe alle und die offenen Nachbarn aus
for row in range(len(layout)):
    for col in range(len(layout[row])):
        alle_nachbarn, offene_nachbarn = nachbarn_und_offene_nachbarn(row, col)
        #print(f"Feld ({row}, {col})")
        #print(f"Alle Nachbarn: {alle_nachbarn}")
        #print(f"Offene Nachbarn: {offene_nachbarn}")
        #print("-" * 40)

# Funktion zum Überprüfen der Verfügbarkeit der Buttons
def setze_verfuegbare_buttons(row, col):
    gefundene_nachbarn, offene_nachbarn = nachbarn_und_offene_nachbarn(row, col)

    # Wenn es zwei offene Nachbarn gibt
    if len(gefundene_nachbarn) == 2:

        # Wenn es nur einen offenen Nachbarn gibt
        if len(offene_nachbarn) == 1:
            # Nur bei 1 offenem Nachbarn: "Drunter", "Drüber", "Gleich" sind verfügbar
            drunter_button.config(state="normal")
            drueber_button.config(state="normal")
            gleich_button.config(state="normal")
            innerhalb_button.config(state="disabled")
            ausserhalb_button.config(state="disabled")

        else:
             # Wenn beide Nachbarn offen sind: "Innerhalb", "Außerhalb" sind verfügbar
            drunter_button.config(state="disabled")
            drueber_button.config(state="disabled")
            gleich_button.config(state="disabled")
            innerhalb_button.config(state="normal")
            ausserhalb_button.config(state="normal")

    # Wenn es drei Nachbarn gibt
    elif len(gefundene_nachbarn) == 3:

        if len(offene_nachbarn) == 1:
            drunter_button.config(state="normal")
            drueber_button.config(state="normal")
            gleich_button.config(state="normal")
            innerhalb_button.config(state="disabled")
            ausserhalb_button.config(state="disabled")
        
        # Wenn zwei Nachbarn offen sind: Prüfen, ob sie im rechten Winkel oder gegenüberliegen
        elif len(offene_nachbarn) == 2:
            sind_nachbarn_reakt_winkel_oder_gegenüber, status = nachbarn_im_rechten_winkel_oder_gegenüber(offene_nachbarn, layout, deck_df)
            
            if sind_nachbarn_reakt_winkel_oder_gegenüber:
                # Falls sie im rechten Winkel oder gegenüber liegen
                drunter_button.config(state="disabled")
                drueber_button.config(state="disabled")
                gleich_button.config(state="disabled")
                innerhalb_button.config(state="normal")
                ausserhalb_button.config(state="normal")
            else:
                # Wenn sie nicht im rechten Winkel oder gegenüber liegen
                drunter_button.config(state="normal")
                drueber_button.config(state="normal")
                gleich_button.config(state="normal")
                innerhalb_button.config(state="disabled")
                ausserhalb_button.config(state="disabled")
        
        # Wenn drei Nachbarn offen sind: "Innerhalb" und "Außerhalb" sind verfügbar
        elif len(offene_nachbarn) == 3:
            drunter_button.config(state="disabled")
            drueber_button.config(state="disabled")
            gleich_button.config(state="disabled")
            innerhalb_button.config(state="normal")
            ausserhalb_button.config(state="normal")
    
    # Wenn es vier Nachbarn gibt
    elif len(gefundene_nachbarn) == 4:
        # Wenn nur ein Nachbar offen ist: "Drunter", "Drüber", "Gleich" sind verfügbar
        if len(offene_nachbarn) == 1:
            drunter_button.config(state="normal")
            drueber_button.config(state="normal")
            gleich_button.config(state="normal")
            innerhalb_button.config(state="disabled")
            ausserhalb_button.config(state="disabled")

        # Wenn zwei Nachbarn offen sind: Prüfen, ob sie im rechten Winkel oder gegenüberliegen
        elif len(offene_nachbarn) == 2:
            sind_nachbarn_reakt_winkel_oder_gegenüber, status = nachbarn_im_rechten_winkel_oder_gegenüber(offene_nachbarn, layout, deck_df)
            
            if sind_nachbarn_reakt_winkel_oder_gegenüber:
                # Falls sie im rechten Winkel oder gegenüber liegen
                drunter_button.config(state="disabled")
                drueber_button.config(state="disabled")
                gleich_button.config(state="disabled")
                innerhalb_button.config(state="normal")
                ausserhalb_button.config(state="normal")
            else:
                # Wenn sie nicht im rechten Winkel oder gegenüber liegen
                drunter_button.config(state="normal")
                drueber_button.config(state="normal")
                gleich_button.config(state="normal")
                innerhalb_button.config(state="disabled")
                ausserhalb_button.config(state="disabled")

        
        # Wenn drei Nachbarn offen sind: "Innerhalb" und "Außerhalb" sind verfügbar
        elif len(offene_nachbarn) == 3:
            drunter_button.config(state="disabled")
            drueber_button.config(state="disabled")
            gleich_button.config(state="disabled")
            innerhalb_button.config(state="normal")
            ausserhalb_button.config(state="normal")

        # Wenn vier Nachbarn offen sind: "Innerhalb" und "Außerhalb" sind verfügbar
        elif len(offene_nachbarn) == 4:
            drunter_button.config(state="disabled")
            drueber_button.config(state="disabled")
            gleich_button.config(state="disabled")
            innerhalb_button.config(state="normal")
            ausserhalb_button.config(state="normal")

# Funktion zum Überprüfen der Nachbarn
def hat_offene_nachbarn(row, col):
    nachbarn = [
        (row-1, col),  # Oben
        (row+1, col),  # Unten
        (row, col-1),  # Links
        (row, col+1)   # Rechts
    ]

    # Überprüfen, ob einer der Nachbarn im Layout existiert und aufgedeckt ist
    for r, c in nachbarn:
        if 0 <= r < len(layout) and 0 <= c < len(layout[r]):
            # Wir durchsuchen den DataFrame nach der Position (r, c)
            index = (deck_df['row'] == r) & (deck_df['col'] == c)

            if index.any():  # Überprüfen, ob der Index existiert
                nachbar_karte = deck_df.loc[index, 'card'].values[0]
                if nachbar_karte is not None:  # Nachbar ist aufgedeckt
                    return True
    return False

# Funktion zum Erstellen der GUI und der Karten
def erstelle_gui():
    for _, row in deck_df.iterrows():
        row_idx = row['row']
        col_idx = row['col']
        kartenwert = row['card']
        
        if kartenwert is None:  # Verdeckte Karte (X)
            label = tk.Button(root, text="X", width=10, height=3, borderwidth=2, relief="solid", font=("Arial", 14), command=lambda r=row_idx, c=col_idx: drehe_karte(r, c))
        else:  # Offene Karte (0)
            label = tk.Label(root, text=kartenwert, width=10, height=3, borderwidth=2, relief="solid", font=("Arial", 14))

        label.grid(row=row_idx, column=col_idx, padx=5, pady=5)

# Funktion zum Umdrehen der Karte
def drehe_karte(row, col):
    # Suche die Karte im DataFrame anhand der Zeile und Spalte
    index = (deck_df['row'] == row) & (deck_df['col'] == col)
    
    if not index.any():
        print(f"Fehler: Keine Karte gefunden für ({row}, {col})")
        return  # Sollte niemals auftreten, aber sicherheitshalber

    if not hat_offene_nachbarn(row, col):
        print("Diese Karte kann nicht aufgedeckt werden, da sie keine offenen Nachbarn hat.")
        return

    card = deck_df.loc[index, 'card'].values[0]

    # Wenn die Karte noch verdeckt ist (None), drehe sie um
    if card is None:
        # Karte umdrehen und den nächsten Wert zuweisen
        new_card = kartenwerte.pop(0)  # Die Karte von der Liste nehmen
        deck_df.loc[index, 'card'] = new_card  # Die Karte im DataFrame aufdecken

        # Überprüfe, welche Buttons verfügbar sind
        setze_verfuegbare_buttons(row, col)
        
        # Gib die Nachbarn und offenen Nachbarn aus
        alle_nachbarn, offene_nachbarn = nachbarn_und_offene_nachbarn(row, col)
        print(f"Feld ({row}, {col})")
        print(f"Alle Nachbarn: {len(alle_nachbarn)}")
        print(f"Offene Nachbarn: {len(offene_nachbarn)}")
        
        # Aktualisiere die GUI
        update_gui()

# Funktion zum Aktualisieren der GUI
def update_gui():
    for _, row in deck_df.iterrows():
        row_idx = row['row']
        col_idx = row['col']
        kartenwert = row['card']

        # Suche das Widget an der Position
        widget = root.grid_slaves(row=row_idx, column=col_idx)[0]
        
        if kartenwert is not None:
            widget.config(text=kartenwert, state="disabled")  # Zeige umgedrehte Karten und verhindere weiteres Klicken
        else:
            widget.config(text="X", state="normal")  # Zeige "X" an, solange sie noch verdeckt ist

# Erstelle das Fenster
root = tk.Tk()
root.title("Fenster Spiel")

# Erstelle die GUI und das Kartenlayout
erstelle_gui()

# Erstelle die Buttons
drunter_button = tk.Button(root, text="Drunter", state="disabled")
drunter_button.grid(row=0, column=6, padx=5, pady=5)

drueber_button = tk.Button(root, text="Drüber", state="disabled")
drueber_button.grid(row=1, column=6, padx=5, pady=5)

gleich_button = tk.Button(root, text="Gleich", state="disabled")
gleich_button.grid(row=2, column=6, padx=5, pady=5)

innerhalb_button = tk.Button(root, text="Innerhalb", state="disabled")
innerhalb_button.grid(row=3, column=6, padx=5, pady=5)

ausserhalb_button = tk.Button(root, text="Außerhalb", state="disabled")
ausserhalb_button.grid(row=4, column=6, padx=5, pady=5)

# Starte die GUI
root.mainloop()