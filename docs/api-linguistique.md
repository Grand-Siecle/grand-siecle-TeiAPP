# API linguistique & NER Grand Siecle

Endpoints pour interroger les annotations linguistiques (lemmes, POS, morphologie) et les entites nommees (NER) extraites automatiquement des documents TEI.

**Base URL :** `http://localhost:8080/exist/apps/GdSiecle`

---

## GET /api/lemma-search

Recherche de mots par lemme, avec contexte de phrase.

### Parametres

| Parametre | Type | Requis | Description |
|-----------|------|--------|-------------|
| `query` | string | oui | Lemme a chercher (regex, insensible a la casse) |
| `lang` | string | non | Filtrer par langue du texte : `lat`, `fra`, `grc` |
| `doc` | string | non | Restreindre a un document par ID interne (ex: `LIV0326_v2`) |
| `start` | int | non | Offset de pagination (defaut: 1) |
| `per-page` | int | non | Resultats par page (defaut: 20) |

### Exemples

Chercher le lemme "inter" :
```
GET /api/lemma-search?query=inter
```

Chercher les lemmes contenant "uirt" en latin :
```
GET /api/lemma-search?query=uirt&lang=lat
```

Chercher "ratio" dans un document specifique :
```
GET /api/lemma-search?query=^ratio$&doc=LIV0326_v2
```

### Reponse

```json
[
  {
    "lemma": "inter",
    "form": "Inter",
    "pos": "PRE",
    "msd": "MORPH=empty",
    "norm": "",
    "lang": "lat",
    "context": "Inter alias vir",
    "document": "Le philosophe indifferent",
    "file": "LIV0326_v2_altos_transcribed_version2.tei.xml"
  }
]
```

| Champ | Description |
|-------|-------------|
| `lemma` | Forme lemmatisee |
| `form` | Forme telle qu'elle apparait dans le texte |
| `pos` | Categorie grammaticale (voir table POS ci-dessous) |
| `msd` | Description morphosyntaxique (`Case=Acc\|Numb=Plur\|Gend=Fem`) |
| `norm` | Forme normalisee (si disponible) |
| `lang` | Langue du passage (`lat`, `fra`, `grc`, `unknown`) |
| `context` | Contexte : phrase (`<s>`) ou extrait du bloc parent |
| `document` | Titre du document |
| `file` | Nom du fichier TEI |

---

## GET /api/pos-concordance

Concordancier : liste tous les mots d'une categorie grammaticale, groupes par lemme avec comptage et formes attestees.

### Parametres

| Parametre | Type | Requis | Description |
|-----------|------|--------|-------------|
| `pos` | string | oui | Tag POS a filtrer (ex: `NOMpro`, `VER`, `ADJqua`) |
| `doc` | string | non | Restreindre a un document |
| `lang` | string | non | Filtrer par langue |

### Exemples

Tous les noms propres en latin :
```
GET /api/pos-concordance?pos=NOMpro&lang=lat
```

Tous les verbes du document LIV0326_v2 :
```
GET /api/pos-concordance?pos=VER&doc=LIV0326_v2
```

### Reponse

```json
[
  {
    "lemma": "Thomus",
    "pos": "NOMpro",
    "count": 11,
    "forms": ["Thom", "Thome", "1.", "q"]
  },
  {
    "lemma": "Decimus",
    "pos": "NOMpro",
    "count": 10,
    "forms": ["D."]
  }
]
```

Trie par nombre d'occurrences decroissant.

---

## GET /api/pos-list

Liste les tags POS disponibles dans le corpus avec leurs comptages. Utile pour peupler des menus deroulants de filtrage.

### Parametres

| Parametre | Type | Requis | Description |
|-----------|------|--------|-------------|
| `doc` | string | non | Restreindre a un document |

### Exemple

```
GET /api/pos-list
```

### Reponse

```json
[
  { "pos": "NOMcom", "count": 730 },
  { "pos": "VER",    "count": 672 },
  { "pos": "NOMpro", "count": 327 },
  { "pos": "ADJqua", "count": 206 },
  { "pos": "PRE",    "count": 197 },
  { "pos": "ADV",    "count": 152 }
]
```

---

## GET /api/search?field=lemma

La recherche standard de TEI Publisher supporte aussi le champ `lemma` via l'index Lucene. Retourne des resultats HTML avec KWIC (keyword in context).

```
GET /api/search?field=lemma&query=ratio
```

---

## Reference POS

Tags de la pipeline linguistique (Pie-extended / LASLA pour le latin) :

| Tag | Description | Exemple |
|-----|-------------|---------|
| `NOMcom` | Nom commun | uirtus, ratio |
| `NOMpro` | Nom propre | Thomus, Aristoteles |
| `VER` | Verbe | habere, esse |
| `ADJqua` | Adjectif qualificatif | bonus, rectus |
| `ADJcar` | Adjectif cardinal | unus, tres |
| `ADJord` | Adjectif ordinal | primus |
| `PRE` | Preposition | inter, in, de |
| `ADV` | Adverbe | praecipue, sic |
| `ADVneg` | Adverbe negatif | non, nec |
| `ADVrel` | Adverbe relatif | ubi, quo |
| `ADVint` | Adverbe interrogatif | cur, quomodo |
| `PROrel` | Pronom relatif | qui, quod |
| `PROdem` | Pronom demonstratif | hic, ille |
| `PROind` | Pronom indefini | alius, quis |
| `PROper` | Pronom personnel | ego, nos |
| `PROpos` | Pronom possessif | suus, meus |
| `PROref` | Pronom reflechi | se, sibi |
| `PROint` | Pronom interrogatif | quis |
| `CONcoo` | Conjonction coordination | et, sed |
| `CONsub` | Conjonction subordination | ut, quod |
| `INJ` | Interjection | o |
| `FOR` | Forme etrangere | |

## Morphologie (MSD)

L'attribut `msd` utilise des paires cle=valeur separees par `|` :

| Cle | Valeurs |
|-----|---------|
| `Case` | Nom, Gen, Dat, Acc, Abl, Voc |
| `Numb` | Sing, Plur |
| `Gend` | Masc, Fem, Neut, MascFem |
| `Tense` | Pres, Imp, Fut, Perf, Plup, FutPerf |
| `Mood` | Ind, Sub, Imp, Inf, Par, Ger, Sup, Gnd |
| `Voice` | Act, Pass |
| `Person` | 1, 2, 3 |
| `Deg` | Pos, Comp, Sup |

Exemple : `Case=Acc|Numb=Plur|Gend=Fem` = accusatif pluriel feminin.

---

## GET /api/document-entities

Extrait toutes les entites NER d'un document : personnes, lieux, organisations, oeuvres, evenements. Combine les declarations du header (particDesc, settingDesc, standOff) avec les comptages de mentions inline et les niveaux de confiance.

### Parametres

| Parametre | Type | Requis | Description |
|-----------|------|--------|-------------|
| `file` | string | oui | Nom du fichier TEI ou ID interne du document |

### Exemple

```
GET /api/document-entities?file=LIV0326_v2_altos_transcribed_version2.tei.xml
```

### Reponse

```json
{
  "summary": {
    "document": "Le philosophe indifferent",
    "file": "LIV0326_v2_altos_transcribed_version2.tei.xml",
    "total-entities": 125,
    "by-type": {
      "person": 88,
      "place": 12,
      "org": 17,
      "work": 5,
      "event": 3
    }
  },
  "entities": [
    {
      "type": "person",
      "id": "pers-779dff30-...",
      "label": "Platon",
      "mentions": 3,
      "certs": ["high", "mid"],
      "source": "ner-auto"
    },
    {
      "type": "place",
      "id": "place-cdecf9db-...",
      "label": "Athenae",
      "mentions": 2,
      "certs": ["high"],
      "source": "ner-auto"
    },
    {
      "type": "person",
      "id": "PERS0075",
      "label": "Antoine de Sommaville",
      "mentions": 0,
      "certs": [],
      "source": "manual"
    }
  ]
}
```

| Champ | Description |
|-------|-------------|
| `type` | Type d'entite : person, place, org, work, event |
| `id` | Identifiant XML (UUID pour NER-auto, ID projet pour manuels) |
| `label` | Nom de l'entite |
| `mentions` | Nombre de mentions inline dans le body du document |
| `certs` | Niveaux de confiance distincts des mentions (high/mid/low) |
| `source` | `ner-auto` (pipeline automatique) ou `manual` (curation) |

Les entites sont triees par nombre de mentions decroissant.

---

## Notes

- Les annotations linguistiques (`<w>`, `<s>`, `<pc>`) sont actuellement presentes surtout dans les passages **latins** du corpus.
- Le pipeline NER (CamemBERT + GLiNER) produit des entites avec un attribut de confiance (`cert`: high/mid/low).
- Les donnees evoluent : la qualite du NER et la couverture du francais seront ameliorees dans les versions futures.
