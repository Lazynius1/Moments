from pathlib import Path
import re, json, html

# Copy approved in the three-screen mockup; update only these feature keys.
ROOT = Path(__file__).resolve().parents[2]
keys = ['requestsTitle', 'requestsReceived', 'requestsSent', 'requestsPending', 'requestsCancel',
        'requestsReceivedFooter', 'requestsSentFooter', 'requestsReceivedEmpty', 'requestsSentEmpty', 'requestsError', 'requestsRetry']
rows = {
'en': 'Group requests|Received|Sent|Pending approval|Cancel request|Accept an invitation to enter the chat.|The group will appear in your conversations when you are accepted.|No pending invitations.|No pending requests sent.|Could not load requests. Check your connection and try again.|Try again',
'es': 'Solicitudes de grupos|Recibidas|Enviadas|Pendiente de aprobación|Cancelar solicitud|Acepta una invitación para entrar al chat.|El grupo aparecerá en tus conversaciones cuando te acepten.|No tienes invitaciones pendientes.|No tienes solicitudes enviadas pendientes.|No se han podido cargar las solicitudes. Comprueba tu conexión e inténtalo de nuevo.|Reintentar',
'ca': 'Sol·licituds de grups|Rebudes|Enviades|Pendent d’aprovació|Cancel·lar sol·licitud|Accepta una invitació per entrar al xat.|El grup apareixerà a les teves converses quan t’acceptin.|No tens invitacions pendents.|No tens sol·licituds enviades pendents.|No s’han pogut carregar les sol·licituds. Comprova la connexió i torna-ho a provar.|Tornar-ho a provar',
'de': 'Gruppenanfragen|Erhalten|Gesendet|Wartet auf Genehmigung|Anfrage zurückziehen|Nimm eine Einladung an, um den Chat zu öffnen.|Die Gruppe erscheint in deinen Unterhaltungen, sobald du aufgenommen wirst.|Keine ausstehenden Einladungen.|Keine ausstehenden gesendeten Anfragen.|Anfragen konnten nicht geladen werden. Prüfe deine Verbindung und versuche es erneut.|Erneut versuchen',
'fr': 'Demandes de groupes|Reçues|Envoyées|En attente d’approbation|Annuler la demande|Acceptez une invitation pour accéder à la discussion.|Le groupe apparaîtra dans vos conversations quand vous serez accepté.|Aucune invitation en attente.|Aucune demande envoyée en attente.|Impossible de charger les demandes. Vérifiez votre connexion et réessayez.|Réessayer',
'it': 'Richieste dei gruppi|Ricevute|Inviate|In attesa di approvazione|Annulla richiesta|Accetta un invito per entrare nella chat.|Il gruppo apparirà nelle tue conversazioni quando verrai accettato.|Nessun invito in sospeso.|Nessuna richiesta inviata in sospeso.|Impossibile caricare le richieste. Controlla la connessione e riprova.|Riprova',
'pt-BR': 'Solicitações de grupos|Recebidas|Enviadas|Aguardando aprovação|Cancelar solicitação|Aceite um convite para entrar no chat.|O grupo aparecerá nas suas conversas quando você for aceito.|Nenhum convite pendente.|Nenhuma solicitação enviada pendente.|Não foi possível carregar as solicitações. Verifique sua conexão e tente novamente.|Tentar novamente',
'pt-PT': 'Pedidos de grupos|Recebidos|Enviados|A aguardar aprovação|Cancelar pedido|Aceita um convite para entrar no chat.|O grupo aparecerá nas tuas conversas quando fores aceite.|Não tens convites pendentes.|Não tens pedidos enviados pendentes.|Não foi possível carregar os pedidos. Verifica a tua ligação e tenta novamente.|Tentar novamente',
'nl': 'Groepsverzoeken|Ontvangen|Verzonden|Wacht op goedkeuring|Verzoek annuleren|Accepteer een uitnodiging om de chat te openen.|De groep verschijnt in je gesprekken zodra je bent toegelaten.|Geen openstaande uitnodigingen.|Geen openstaande verzonden verzoeken.|Verzoeken konden niet worden geladen. Controleer je verbinding en probeer het opnieuw.|Opnieuw proberen',
'pl': 'Prośby dotyczące grup|Otrzymane|Wysłane|Oczekuje na zatwierdzenie|Anuluj prośbę|Zaakceptuj zaproszenie, aby wejść na czat.|Grupa pojawi się w Twoich rozmowach po zaakceptowaniu prośby.|Brak oczekujących zaproszeń.|Brak oczekujących wysłanych próśb.|Nie udało się wczytać próśb. Sprawdź połączenie i spróbuj ponownie.|Spróbuj ponownie',
'ja': 'グループへの申請|受信|送信|承認待ち|申請を取り消す|招待を承認するとチャットに参加できます。|承認されると、グループが会話一覧に表示されます。|保留中の招待はありません。|保留中の送信済み申請はありません。|申請を読み込めませんでした。接続を確認して再試行してください。|再試行',
'ko': '그룹 요청|받은 요청|보낸 요청|승인 대기 중|요청 취소|초대를 수락하면 채팅에 참여할 수 있습니다.|승인되면 그룹이 대화 목록에 표시됩니다.|대기 중인 초대가 없습니다.|대기 중인 보낸 요청이 없습니다.|요청을 불러오지 못했습니다. 연결을 확인하고 다시 시도하세요.|다시 시도',
'zh-Hant': '群組申請|已收到|已傳送|等待核准|取消申請|接受邀請即可進入聊天。|獲得核准後，群組會出現在你的對話列表中。|沒有待處理的邀請。|沒有等待核准的已傳送申請。|無法載入申請。請檢查連線後重試。|重試',
'hi': 'समूह के अनुरोध|प्राप्त|भेजे गए|स्वीकृति की प्रतीक्षा में|अनुरोध रद्द करें|चैट में प्रवेश करने के लिए आमंत्रण स्वीकार करें।|आपका अनुरोध स्वीकार होने पर समूह आपकी बातचीत में दिखाई देगा।|कोई लंबित आमंत्रण नहीं है।|कोई भेजा गया अनुरोध लंबित नहीं है।|अनुरोध लोड नहीं हो सके। अपना कनेक्शन जाँचें और फिर से कोशिश करें।|फिर से कोशिश करें',
'id': 'Permintaan grup|Diterima|Dikirim|Menunggu persetujuan|Batalkan permintaan|Terima undangan untuk masuk ke chat.|Grup akan muncul di percakapan Anda setelah Anda diterima.|Tidak ada undangan tertunda.|Tidak ada permintaan terkirim yang tertunda.|Permintaan tidak dapat dimuat. Periksa koneksi Anda dan coba lagi.|Coba lagi',
 'tr': 'Grup istekleri|Gelen|Gönderilen|Onay bekliyor|İsteği iptal et|Sohbete girmek için bir daveti kabul et.|Kabul edildiğinde grup konuşmalarında görünecek.|Bekleyen davet yok.|Bekleyen gönderilmiş istek yok.|İstekler yüklenemedi. Bağlantını kontrol edip tekrar dene.|Tekrar dene',
}
qual={'en':'values','id':'values-in','pt-BR':'values-b+pt+BR','pt-PT':'values-b+pt+PT','zh-Hant':'values-b+zh+Hant'}
def resource(key): return 'groups_'+re.sub(r'(?<!^)(?=[A-Z])','_',key).lower()
for lang,row in rows.items():
    values=row.split('|')
    if len(values)!=len(keys): raise ValueError(lang)
    ios=ROOT/'Moments/Moments'/f'{lang}.lproj/Localizable.strings'
    text=ios.read_text()
    android=ROOT/'MomentsAndroid/app/src/main/res'/qual.get(lang,'values-'+lang)/'strings_groups.xml'
    xml=android.read_text()
    for key,value in zip(keys,values):
        text=re.sub(r'^"groups\.'+re.escape(key)+r'" = .*;\n?', '', text, flags=re.M)
        text+='"groups.'+key+'" = '+json.dumps(value,ensure_ascii=False)+';\n'
        res=resource(key)
        xml=re.sub(r'\s*<string name="'+res+r'">.*?</string>', '', xml)
        escaped=html.escape(value,quote=False).replace("'", "\\'").replace('"','\\"')
        xml=xml.replace('</resources>',f'    <string name="{res}">{escaped}</string>\n</resources>')
    ios.write_text(text);android.write_text(xml)
p=ROOT/'MomentsAndroid/app/src/main/java/com/moments/android/views/messaging/groups/GroupStrings.kt'
s=p.read_text()
for key in keys:
    if f'"{key}" ->' not in s: s=s.replace('    else ->',f'    "{key}" -> R.string.{resource(key)}\n    else ->')
p.write_text(s)
print(f'{len(keys)} texts synced in {len(rows)} locales for both apps.')
