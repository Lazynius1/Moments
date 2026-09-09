from pathlib import Path
import re, json, html
ROOT = Path(__file__).resolve().parents[2]
keys = ['inviteLink','linkBody','getLink','shareLink','renewLink','disableLink','joinLink','linkError','notice.joined','notice.left','notice.removed']
rows = {
'en': 'Invitation link|Anyone with this link can join and read the group history. Renewing or disabling it invalidates the previous link.|Get link|Share link|Renew link|Disable link|Join group|This link is unavailable, the group is full, or your chat keys could not be loaded. Try again or ask an admin for a new link.|%@ joined the group|%@ left the group|%@ was removed from the group',
'es': 'Enlace de invitación|Cualquiera que tenga este enlace puede unirse y leer el historial del grupo. Renovarlo o desactivarlo invalida el enlace anterior.|Obtener enlace|Compartir enlace|Renovar enlace|Desactivar enlace|Unirme al grupo|Este enlace no está disponible, el grupo está lleno o no se han podido cargar tus claves del chat. Inténtalo de nuevo o pide otro enlace a un admin.|%@ se ha unido al grupo|%@ ha salido del grupo|Se ha expulsado a %@ del grupo',
'ca': 'Enllaç d’invitació|Qualsevol persona amb aquest enllaç pot unir-se i llegir l’historial del grup. Renovar-lo o desactivar-lo invalida l’enllaç anterior.|Obtenir enllaç|Compartir enllaç|Renovar enllaç|Desactivar enllaç|Unir-me al grup|L’enllaç no està disponible, el grup és ple o no s’han pogut carregar les claus del xat. Torna-ho a provar o demana un enllaç nou a un admin.|%@ s’ha unit al grup|%@ ha sortit del grup|S’ha expulsat %@ del grup',
'de': 'Einladungslink|Alle mit diesem Link können beitreten und den Gruppenverlauf lesen. Erneuern oder Deaktivieren macht den bisherigen Link ungültig.|Link abrufen|Link teilen|Link erneuern|Link deaktivieren|Gruppe beitreten|Dieser Link ist nicht verfügbar, die Gruppe ist voll oder deine Chatschlüssel konnten nicht geladen werden. Versuche es erneut oder bitte einen Admin um einen neuen Link.|%@ ist der Gruppe beigetreten|%@ hat die Gruppe verlassen|%@ wurde aus der Gruppe entfernt',
'fr': 'Lien d’invitation|Toute personne disposant de ce lien peut rejoindre le groupe et lire son historique. Le renouveler ou le désactiver invalide le lien précédent.|Obtenir le lien|Partager le lien|Renouveler le lien|Désactiver le lien|Rejoindre le groupe|Ce lien est indisponible, le groupe est complet ou vos clés de discussion n’ont pas pu être chargées. Réessayez ou demandez un nouveau lien à un admin.|%@ a rejoint le groupe|%@ a quitté le groupe|%@ a été exclu du groupe',
'it': 'Link di invito|Chiunque abbia questo link può unirsi e leggere la cronologia del gruppo. Rinnovarlo o disattivarlo invalida il link precedente.|Ottieni link|Condividi link|Rinnova link|Disattiva link|Unisciti al gruppo|Il link non è disponibile, il gruppo è pieno o non è stato possibile caricare le chiavi della chat. Riprova o chiedi un nuovo link a un admin.|%@ si è unito al gruppo|%@ ha lasciato il gruppo|%@ è stato rimosso dal gruppo',
'pt-BR': 'Link de convite|Qualquer pessoa com este link pode entrar e ler o histórico do grupo. Renovar ou desativar o link invalida o anterior.|Obter link|Compartilhar link|Renovar link|Desativar link|Entrar no grupo|Este link está indisponível, o grupo está cheio ou não foi possível carregar suas chaves do chat. Tente novamente ou peça um novo link a um admin.|%@ entrou no grupo|%@ saiu do grupo|%@ foi removido do grupo',
'pt-PT': 'Ligação de convite|Qualquer pessoa com esta ligação pode entrar e ler o histórico do grupo. Renovar ou desativar a ligação invalida a anterior.|Obter ligação|Partilhar ligação|Renovar ligação|Desativar ligação|Entrar no grupo|Esta ligação está indisponível, o grupo está cheio ou não foi possível carregar as tuas chaves do chat. Tenta novamente ou pede uma nova ligação a um admin.|%@ entrou no grupo|%@ saiu do grupo|%@ foi removido do grupo',
'nl': 'Uitnodigingslink|Iedereen met deze link kan deelnemen en de groepsgeschiedenis lezen. Vernieuwen of uitschakelen maakt de vorige link ongeldig.|Link ophalen|Link delen|Link vernieuwen|Link uitschakelen|Deelnemen aan groep|Deze link is niet beschikbaar, de groep is vol of je chatsleutels konden niet worden geladen. Probeer opnieuw of vraag een beheerder om een nieuwe link.|%@ is lid geworden van de groep|%@ heeft de groep verlaten|%@ is uit de groep verwijderd',
'pl': 'Link z zaproszeniem|Każdy, kto ma ten link, może dołączyć i przeczytać historię grupy. Odnowienie lub wyłączenie unieważnia poprzedni link.|Pobierz link|Udostępnij link|Odnów link|Wyłącz link|Dołącz do grupy|Link jest niedostępny, grupa jest pełna lub nie udało się wczytać kluczy czatu. Spróbuj ponownie lub poproś administratora o nowy link.|%@ dołączył(a) do grupy|%@ opuścił(a) grupę|%@ został(a) usunięty(-a) z grupy',
'ja': '招待リンク|このリンクを持つ人は誰でも参加してグループの履歴を読めます。更新または無効化すると以前のリンクは使えなくなります。|リンクを取得|リンクを共有|リンクを更新|リンクを無効化|グループに参加|リンクが利用できないか、グループが満員か、チャットの鍵を読み込めませんでした。再試行するか、管理者に新しいリンクを依頼してください。|%@がグループに参加しました|%@がグループを退出しました|%@がグループから削除されました',
'ko': '초대 링크|이 링크가 있는 누구나 참여하고 그룹 기록을 읽을 수 있습니다. 갱신하거나 비활성화하면 이전 링크는 사용할 수 없습니다.|링크 가져오기|링크 공유|링크 갱신|링크 비활성화|그룹 참여|링크를 사용할 수 없거나 그룹이 가득 찼거나 채팅 키를 불러오지 못했습니다. 다시 시도하거나 관리자에게 새 링크를 요청하세요.|%@님이 그룹에 참여했습니다|%@님이 그룹을 나갔습니다|%@님이 그룹에서 삭제되었습니다',
'zh-Hant': '邀請連結|任何擁有此連結的人都可以加入並閱讀群組記錄。更新或停用會使先前的連結失效。|取得連結|分享連結|更新連結|停用連結|加入群組|此連結無法使用、群組已滿，或無法載入聊天金鑰。請重試或向管理員索取新連結。|%@已加入群組|%@已離開群組|%@已被移出群組',
'hi': 'आमंत्रण लिंक|इस लिंक वाला कोई भी व्यक्ति जुड़ सकता है और समूह का इतिहास पढ़ सकता है। इसे बदलने या बंद करने से पुराना लिंक अमान्य हो जाता है।|लिंक प्राप्त करें|लिंक साझा करें|नया लिंक बनाएँ|लिंक बंद करें|समूह में शामिल हों|यह लिंक उपलब्ध नहीं है, समूह भर गया है या आपकी चैट कुंजियाँ लोड नहीं हो सकीं। फिर से कोशिश करें या एडमिन से नया लिंक माँगें।|%@ समूह में शामिल हुए|%@ ने समूह छोड़ दिया|%@ को समूह से हटा दिया गया',
'id': 'Tautan undangan|Siapa pun yang memiliki tautan ini dapat bergabung dan membaca riwayat grup. Memperbarui atau menonaktifkannya membatalkan tautan sebelumnya.|Dapatkan tautan|Bagikan tautan|Perbarui tautan|Nonaktifkan tautan|Gabung grup|Tautan ini tidak tersedia, grup penuh, atau kunci chat tidak dapat dimuat. Coba lagi atau minta tautan baru dari admin.|%@ bergabung dengan grup|%@ keluar dari grup|%@ dikeluarkan dari grup',
 'tr': 'Davet bağlantısı|Bu bağlantıya sahip herkes katılabilir ve grup geçmişini okuyabilir. Yenilemek veya devre dışı bırakmak önceki bağlantıyı geçersiz kılar.|Bağlantıyı al|Bağlantıyı paylaş|Bağlantıyı yenile|Bağlantıyı devre dışı bırak|Gruba katıl|Bu bağlantı kullanılamıyor, grup dolu veya sohbet anahtarlarınız yüklenemedi. Tekrar deneyin ya da yöneticiden yeni bir bağlantı isteyin.|%@ gruba katıldı|%@ gruptan ayrıldı|%@ gruptan çıkarıldı',
}
qual={'en':'values','id':'values-in','pt-BR':'values-b+pt+BR','pt-PT':'values-b+pt+PT','zh-Hant':'values-b+zh+Hant'}
def resource(k): return 'groups_'+re.sub(r'(?<!^)(?=[A-Z])','_',k).lower().replace('.','_')
for lang,row in rows.items():
    values=row.split('|'); assert len(values)==len(keys)
    ios=ROOT/'Moments/Moments'/f'{lang}.lproj/Localizable.strings'
    text=ios.read_text()
    android=ROOT/'MomentsAndroid/app/src/main/res'/qual.get(lang,'values-'+lang)/'strings_groups.xml'
    xml=android.read_text()
    for key,value in zip(keys,values):
        text=re.sub(r'^"groups\.'+re.escape(key)+r'" = .*;\n?', '', text, flags=re.M)
        text+='"groups.'+key+'" = '+json.dumps(value,ensure_ascii=False)+';\n'
        res=resource(key)
        xml=re.sub(r'\s*<string name="'+res+r'">.*?</string>', '', xml)
        escaped=html.escape(value.replace('%@','%1$s'),quote=False).replace("'", "\\'").replace('"','\\"')
        xml=xml.replace('</resources>',f'    <string name="{res}">{escaped}</string>\n</resources>')
    ios.write_text(text);android.write_text(xml)
p=ROOT/'MomentsAndroid/app/src/main/java/com/moments/android/views/messaging/groups/GroupStrings.kt'
s=p.read_text()
for key in keys:
    if f'"{key}" ->' not in s: s=s.replace('    else ->',f'    "{key}" -> R.string.{resource(key)}\n    else ->')
p.write_text(s)
