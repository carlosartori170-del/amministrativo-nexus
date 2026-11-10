# Premio Individuale Mensile PDR Cameri 2026

Rilascio coordinato del 10 novembre 2026, approvato da Carlo.
Supabase autorizzato: `eqtyfnluswalfassmlxd`.

## Accesso e utilizzo

In Gestione Ore selezionare Cameri e aprire **PDR Cameri 2026** (solo admin attivo).
I dodici mesi iniziano da classificare: indicare esplicitamente quelli già pagati;
non vengono ricostruiti importi storici. Aprire gli altri mesi prima dell'anteprima.

In Amministrativo Nexus aprire la persona di magazzino e **Welfare e PDR 2026**.
Verificare gli importi annuali esterni e PDR pregressi prima di dichiarare completa
la ricognizione. Le eccezioni malattia con motivazione riservata sono gestite qui.

L'anteprima non impegna welfare. La chiusura congela gli importi e impegna il saldo;
la marcatura pagato sposta l'impegno tra gli importi utilizzati senza duplicarlo.
Non esiste riapertura di mesi chiusi, pagati o storici.

## Regole e integrazioni

Fonte economica unica: funzioni SQL del modulo, non formule replicate nel client.
Attività/reparto 56/7, 63/8 e 70/9; pesi 1, 1.125 e 6.
Timeline consuntiva divisa per giorno di calendario; PreTurno escluso.
Riproporzionamento per scaglioni 25/50/75/100/125/150 ore, come addendum.
Produttività completa: <=180 zero; (180,190] prima fascia, e così via; massimo 12.
Assunzione dopo il primo giorno: mese di ingresso non maturato.
Malattia annulla salvo eccezione amministrativa documentata.

Abbinamenti autorizzati per il modulo: Voice 23093 -> ID 1806;
Voice 23233 -> ID 1810. Gli ID inattivi e lo storico non vengono modificati.
Le duplicazioni anagrafiche restano segnalate informativamente nell'anteprima;
l'attribuzione dei colli usa la mappa esplicita mensile.

Il Gestionale non interroga figli, dichiarazioni, note familiari o motivazioni
sanitarie. Il controllo server è NexusProfili con Ruolo=admin e Attivo=true.
Nessuna modifica al Portale Clienti o alle quattro tabelle protette Cassano.

## Validazione eseguita

- 53 controlli del motore su PostgreSQL embedded con dati sintetici.
- 12 controlli UI con DOM simulato e RPC finte.
- 8 suite di regressione già presenti del Gestionale.
- Anteprima browser con dati sintetici: schermate PDR, welfare e blocco responsabile.
- RLS effettive verificate in transazioni senza scritture persistenti per admin,
  responsabile e rete_gestore; anon senza grant; UPDATE/TRUNCATE client revocati.
- Funzione sorgenti eseguita in sola lettura su ottobre: 42 persone,
  549 segmenti ore e 567 righe produzione. Nessun premio reale calcolato.
- Metadati RLS/ACL delle quattro tabelle Cassano confrontati: invariati.

Non sono stati effettuati pagamenti, classificazioni mesi o caricamenti di dati
familiari. Il flusso completo con dati economici effettivi e le gare tra due
connessioni richiedono l'apertura autorizzata del primo mese da calcolare.

## SQL e rollback

Gli SQL nel percorso `sql/` sono conservati per ripristino e verifica, non devono
essere eseguiti di nuovo su un modulo già installato.
La configurazione Voice è stata eseguita e tracciata nell'audit.
Il rollback operativo revoca le nuove API e conserva lo storico. Il rollback
strutturale rifiuta di cancellare il modulo se contiene dati o audit.

Versioni precedenti: Gestionale Sites 37, commit
`6ed165536ee9cd33d54ba7bca2e86288b68a39a3`; Amministrativo main
`3c305888327717b80b0b60425638007658ed8fab`.

Il backup applicativo include le tabelle public ma non il codice dello schema
privato: conservare gli SQL insieme al codice delle app.
