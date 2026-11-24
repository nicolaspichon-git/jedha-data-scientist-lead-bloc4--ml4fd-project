
*MACHINE LEARNING FOR FRAUD DETECTION* PROJECT
===

# D1.A Monitoring Architecture

> *Nicolas Pichon --- AIA RNCP 38777 / BC04 / D1 : Monitoring Architecture / v01 --- 2026/11/26.*
---

> Sources : `airflow/dags/dag_monitor.py`, `ml4fd/monitor.py`, `sql/monitoring/*.sql`,
> et section `monitoring` de `governance.yml`. 

*Notations* :

| Notation | Nature | Ce qu'une rupture donne |
|---|---|---|
| `──▶` trait plein | **flux de données** | une mesure absente, un contrôle non mesurable |
| `══▶` trait gras | **flux de contrôle** | la boucle mesure, alerte, et ne réentraîne rien |
| `╌╌▶` pointillé | **dépendance** | une mesure incomparable, ou un seuil qui juge le passé |

## Le diagramme
  

<div style="page-break-after: always;"></div>

###### overview
```mermaid
flowchart TB
    sources[("Measured sources <i>PostgreSQL</i>")]

    ref[("Datasets:<br/><i>parquets</i> of <i>champion</i>,<br/><i>drift</i> reference")]
    mlflow[("<i>mlflow</i><br/><i>champion</i> alias")]   
    gov["<b>governance.yml</b><br/>mode, seuils, retrain_on,<br/>cooldown, not_comparable"]
    service["<b>scoring-service</b><br/><i>FastAPI</i>"]

    dag{{"<b>dag_monitor</b>"}}
    familles["Measures<br/><i>SQL</i>"]
    journaux[("Journaux<br/><i>PostgreSQL</i>")]
    train{{"<b>dag_train</b>"}}
    page["<b>dashboard</b><br/><i>Streamlit</i>"]

    %% ---------- flux de donnees
    sources -->|"features_window.sql,<br/>flag_rate_window.sql,<br/>performance_window.sql,<br/>checks/pipeline_health.sql"| familles
    ref -->|"reference frame"| familles

    familles --> dag
  
    dag -->|"one row per measure,<br/>state of each control,<br/>what changed + new state,<br/>controls + reason,"| journaux
    journaux -->|"last_retrain_request.sql,<br/>recorded states"| dag
    journaux --> page
    
    mlflow -->|"load <i>champion</i>"| service
    service -->|"the measured scores are the<br/>service answers, written by dag_ingest"| sources
    
    %% ---------- flux de controle
    dag ==>|"trigger"| train
    train ==>|"challenge and promote: move alias if promotion"| mlflow

    %% ---------- dependances    

    mlflow -.->|"which model is served"| dag
    mlflow -.->|"the reference follows the champion: a promotion moves it"| ref
    train -.->|"paused: the trigger<br/>succeeds and nothing trains"| dag

    gov -.->|"thresholds, floor,<br/>comparable columns,<br/>retrain_on, cooldown"| dag
    
    classDef sortie fill:#1f6f43,stroke:#0d3b24,color:#ffffff
    classDef tableau fill:#1f3a6f,stroke:#0d1d3b,color:#ffffff
    classDef attention fill:#7a2f2f,stroke:#3b1414,color:#ffffff
    class journaux sortie
    class service sortie
    class sources tableau
```

<div style="page-break-after: always;"></div>

###### details 1 : measures

```mermaid
flowchart TB
    subgraph sources["Measured sources"]
        txn[("fd_transactions<br/><i>the served window</i>")]
        scores[("fd_scores")]
        vue[/"<i>fd_scoring_decisions</i> view"/]
        truth[("fd_ground_truth")]
        frauds[("fd_frauds")]
        runs[("fd_pipeline_runs")]
        quar[("fd_quarantine<br/><i>counts only</i>")]
    end

    ref[("datasets:<br/>champion's train.parquet<br/><i>drift reference</i>")]
    evi["<b>evidently</b> 0.7.23<br/>PSI pinned"]
    service["<b>scoring-service</b>"]

    subgraph familles["Measures<br/><i>SQL</i>"]
        d1["input_drift<br/>share of drifted columns"]
        d2["prediction_drift<br/>alert rate / published rate"]
        d3["performance<br/>recall vs min_recall"]
        d4["data_quality<br/><i>copy of the N9 controls</i>"]
    end

    %% ---------- flux de donnees
    txn -->|"features_window.sql"| d1
    ref -->|"reference frame"| d1
    scores -->|"flag_rate_window.sql"| d2
    txn --> d2
    truth -->|"performance_window.sql"| d3
    scores --> d3
    frauds --> d3
    runs -->|"checks/pipeline_health.sql<br/>via health.facts_of"| d4
    quar --> d4
    txn --> d4

    scores --> vue
    
    service -->|"the measured scores are the<br/>service answers, written by dag_ingest"| scores
    
    %% ---------- dependances
    evi -.->|"the statistic and its limit,<br/>copied into every row"| d1


    classDef sortie fill:#1f6f43,stroke:#0d3b24,color:#ffffff
    classDef tableau fill:#1f3a6f,stroke:#0d1d3b,color:#ffffff
    classDef attention fill:#7a2f2f,stroke:#3b1414,color:#ffffff
    class monit,state,notif,req sortie
    class service sortie
    class txn,scores,truth,frauds,runs,quar tableau
    class decide attention
```

<div style="page-break-after: always;"></div>

###### details 2 : monitoring & retraining

```mermaid
flowchart TB

    familles["Measures<br/><i>SQL</i>"]
    
    subgraph dag["<b>dag_monitor</b>"]
        champion["<b>champion</b>"]
        measure["<b>measure</b>"]
        tell["<b>tell</b><br/>notify the channel"]
        decide{"<b>decide:</b><br/>retrain_on alert?"}
        ask["<b>ask_for_retraining</b>"]
        none["<b>no_retraining</b>"]
        rec["<b>record_request</b>"]
    end
    
    train{{"<b>dag_train</b>"}}
    
    journaux["Journaux"]
    
    mlflow[("<b><i>mlflow</i></b> : <i>champion</i> alias")]
    gov["governance.yml<br/>mode, seuils, retrain_on,<br/>cooldown, not_comparable"]

    %% ---------- flux de donnees
    champion -->|"served features,<br/>published alerts_per_day,<br/>dataset version"| measure
    familles --> measure
    measure -->|"one row per measure"| journaux
	journaux -->|"last recorded state<br/>of each control"| measure
	tell -->|"new state,<br/>after sending"| journaux

    tell -->|"what changed"| journaux
    rec -->|"controls + reason"| journaux
    journaux -->|"last_retrain_request.sql"| decide

    %% ---------- flux de controle
    measure ==> tell
	measure ==>|"report<br/>recorded states"| decide
    decide ==>|"yes"| ask
    decide ==>|"no"| none
    ask ==>|"trigger"| train
    ask ==>|"then register"| rec
    train ==>|"challenge and promote: move alias if promotion"| mlflow

    %% ---------- dependances
    mlflow -.->|"which model is served"| champion
    gov -.->|"thresholds, floor,<br/>comparable columns"| measure
    gov -.->|"retrain_on: [input_drift, performance],<br/>cooldown"| decide
    train -.->|"paused: the trigger<br/>succeeds and nothing trains"| ask

    classDef sortie fill:#1f6f43,stroke:#0d3b24,color:#ffffff
    classDef tableau fill:#1f3a6f,stroke:#0d1d3b,color:#ffffff
    classDef attention fill:#7a2f2f,stroke:#3b1414,color:#ffffff
    class journaux sortie
    class decide attention
```

<div style="page-break-after: always;"></div>

###### details 3 : journaux

```mermaid
flowchart TB
    subgraph dag["<b>dag_monitor</b>"]
        measure["<b>measure</b>"]
        tell["<b>tell</b><br/>notify the channel"]
        decide{"<b>decide</b>"}
        ask["<b>ask_for_retraining</b>"]
        rec["<b>record_request</b>"]
    end

    subgraph journaux["Journaux"]
        monit[("fd_monitoring<br/><i>every measure, with its limit</i>")]
        state[("fd_ops_state")]
        notif[("fd_ops_notifications")]
        req[("fd_retrain_requests")]
    end

    page["<b>dashboard</b><br/><i>Streamlit</i>"]

    %% ---------- flux de donnees
    measure -->|"one row per measure"| monit
	state -->|"last recorded state<br/>of each control"| measure
	tell -->|"new state,<br/>after sending"| state
    tell -->|"what changed"| notif
    rec -->|"controls + reason"| req
    req -->|"last_retrain_request.sql"| decide

    monit --> page
    state --> page
    req --> page

    %% ---------- flux de controle
    measure ==> tell
	measure ==>|"report<br/>recorded states"| decide
    decide ==>|"yes"| ask
    ask ==>|"then register"| rec

    classDef sortie fill:#1f6f43,stroke:#0d3b24,color:#ffffff
    classDef tableau fill:#1f3a6f,stroke:#0d1d3b,color:#ffffff
    classDef attention fill:#7a2f2f,stroke:#3b1414,color:#ffffff
    class monit,state,notif,req sortie
    class service sortie
    class decide attention
```


###### details 4 : models registry closed loop 

```mermaid
flowchart TB

	evi["<i>evidently</i>"]
    scores[("<b>fd_scores</b>")]
    familles["Measures<br/><i>SQL</i>"]

    ref[("Datasets:<br/>train.parquet of <i>champion</i><br/><i>drift</i> reference")]
    mlflow[("<i>mlflow</i><br/><i>champion</i> alias")]
    service["<b>scoring-service</b>"]

    dag{{"<b>dag_monitor</b>"}}
    train{{"<b>dag_train</b>"}}

    journaux[("Journaux")]
   
    %% ---------- flux de donnees
    familles --> dag
    ref -->|"reference frame"| familles
    scores -->|"flag_rate_window.sql"| familles
    mlflow -->|"load <i>champion</i>"| service
    dag -->|"controls + reason"| journaux
    journaux -->|"last_retrain_request.sql,<br/>last recorded state of each control"| dag

    %% ---------- flux de controle
    dag ==>|"trigger"| train
    train ==>|"challenge and promote: move alias if promotion"| mlflow

    %% ---------- dependances
    mlflow -.->|"which model is served"| dag
    mlflow -.->|"the reference follows the champion: a promotion moves it"| ref
    train -.->|"paused: the trigger succeedd and nothing trains"| dag
    service -.->|"the measured scores are the service answers, written by <i>dag_ingest</i>"| scores
    evi -.->|"the statistic and its limit,<br/>copied into every row"| familles
    
    classDef sortie fill:#1f6f43,stroke:#0d3b24,color:#ffffff
    classDef tableau fill:#1f3a6f,stroke:#0d1d3b,color:#ffffff
    classDef attention fill:#7a2f2f,stroke:#3b1414,color:#ffffff
    class scores tableau
    class journaux sortie
    class service sortie
```


<div style="page-break-after: always;"></div>

## Ce que le diagramme dit

### `tell` et `decide` sont frères, pas en file

Les deux descendent de `measure` et ne se commandent pas l'un l'autre : `tell` peut déjà avoir commité la transition d'état, `decide` échoue sur la tâche suivante, et tous les passages ultérieurs ont mesuré la même alerte, n'ont trouvé aucune transition, et n'ont rien demandé. Une panne, et la demande était perdue pour de bon.

La règle de `decide` ne lit donc plus une transition mais une **alerte non répondue** : `fd_retrain_requests` est interrogée (`last_retrain_request.sql`), et c'est la flèche de `req` vers `decide` sur le diagramme. Elle rend la décision idempotente.

### Déclencher, puis consigner

`ask ══▶ rec` et non l'inverse. L'enregistrement suit le déclenchement, donc
une panne entre les deux **sous-estime** ce qui s'est passé au lieu
d'affirmer quelque chose qui n'a pas eu lieu. Une demande consignée pour un
réentraînement jamais déclenché serait un mensonge ; un réentraînement
déclenché non consigné est un trou, ce qui est la direction sûre.

### La référence suit le champion

`mlflow ╌╌▶ ref` porte la conséquence : la référence de dérive est le
`train.parquet` **de la recette du modèle en service**, trouvée par son
manifeste. Une promotion la déplace. C'est voulu — mesurer la dérive contre le
corpus d'un modèle que personne ne fait tourner ne dit rien — mais cela
signifie qu'un écart au repos n'est pas une constante : il change à chaque
promotion.

### Deux familles ne déclenchent rien

`retrain_on: [input_drift, performance]`. `prediction_drift` et `data_quality` sont mesurées, enregistrées, notifiées - et ne déclenchent pas. Une dérive du taux d'alerte appelle un seuil à rechoisir, pas un modèle à réajuster ; une alerte de qualité appelle le flux à réparer, et réentraîner sur un flux cassé apprendrait la casse.

C'est la raison pour laquelle l'injection de dérive du 20/11 se voyait parfaitement dans `prediction_drift` - 864 alertes/jour contre une limite de 151,8 - sans rien déclencher.

### La flèche rouge du diagramme

`train ╌╌▶ ask` est dessinée à l'envers du flux exprès. Un `dag_train` **en
pause** fait **réussir** le `TriggerDagRunOperator` : le run reste en file,
`record_request` consigne la demande, et rien n'entraîne. Trois fois ce piège
s'est refermé dans la même journée, à trois maillons différents.
`fd-manager.ps1 monitor -Apply` active `dag_train` pour cette raison.

### Ce qui est surveillé est ce que le service a répondu

Avec le découplage, le pipeline `dag_ingest` appelle `/score/batch` et écrit les réponses du
service. `prediction_drift` et `performance` mesurent donc le **service**, et non plus un second modèle chargé dans le scheduler.

Deux conséquences d'exploitation à retenir :

- Une panne du service ne produit pas une mesure fausse, elle produit une   fenêtre sans mesure. `score_batch` est rouge, aucune ligne n'entre dans   `fd_scores`, et `prediction_drift` se mesure sur ce qui a été scoré avant.  Le contrôle ne passe pas en alerte : il n'a rien à juger. C'est
  `data_quality`, qui lit `fd_pipeline_runs`, qui voit la panne ;
- La latence du service est maintenant dans le chemin critique du pipeline. Un service lent allonge `score_batch` sans rien faire sortir d'une limite. Aucun des quatre contrôles ne regarde un temps de réponse - c'est précisément le rôle de l'exigence *B4-EC43*.

### Les appels tiers ne sont pas surveillés, et ce n'est pas un oubli

`fd_scoring_decisions` est sur le diagramme en gris : la vue existe et la
surveillance ne la lit pas. Elle lit `fd_scores` seule.

La raison n'est pas la paresse, c'est l'absence de population. Les deux
contrôles qui pourraient s'y intéresser ont tous deux besoin de quelque chose
qu'un appel tiers n'a pas :

- `performance` compare aux verdicts de `fd_ground_truth`. Un paiement soumis
  par un tiers n'est pas une transaction du pipeline : personne ne dira jamais
  s'il était frauduleux. Mesurer un rappel dessus serait mesurer sur zéro
  positif connu ;
- `prediction_drift` compare un taux d'alerte au taux publié, qui est une
  grandeur **par jour sur le flux servi**. Les appels tiers n'ont ni cadence ni
  volume déclarés — un tiers qui appelle dix fois en une minute ferait sortir le
  taux de ses bornes sans qu'aucune dérive se soit produite.

Surveiller le service pour lui-même demande d'autres grandeurs que celles de la boucle modèle : disponibilité, latence, part de 422. C'est B4-EC43 et c'est un cinquième `control`, pas une extension des quatre familles — ce qui impose une migration du `CHECK` de `fd_monitoring`.

### La limite évolue avec la mesure

Chaque ligne de `fd_monitoring` porte la limite qui était en vigueur au moment de la mesure, et non celle d'aujourd'hui. `max_drifted_share` est passé de 0,40 à 0,70 le 20/11 : relire le seuil en gouvernance à l'affichage redessinerait le passé contre la règle actuelle, et une série dont la limite bouge en silence n'est pas lisible. 
C'est aussi ce qui donne un sens à B4-EC45 : constater une évolution implique que l'unité de base ne change pas silencieusement.
