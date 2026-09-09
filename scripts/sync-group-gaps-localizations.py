#!/usr/bin/env python3
"""Idempotent group-gap copy for iOS + Android (16 locales)."""
from pathlib import Path
import json, re, html

ROOT = Path(__file__).resolve().parents[2]
keys = [
    "typing.one", "typing.two", "typing.several",
    "searchMembers", "noMembersFound",
    "mention.placeholder", "notification.mention",
    "description", "descriptionPlaceholder",
    "send.everyone", "send.admins", "send.locked",
    "dissolve", "dissolveBody", "notice.dissolved",
    "mute.8h", "mute.week", "mute.always",
    "link.approval", "join.requested", "joinRequests",
    "approveJoin", "report", "report.subtitle",
]
rows = {
"en": "%@ is typing…|%@ and %@ are typing…|Several people are typing…|Search members|No members found.|Mention a member|%@ mentioned you|Description|Add a description|Everyone can send|Only admins can send|Only admins can send messages|Delete group|This deletes the group for everyone. Previously downloaded messages cannot be erased from their devices.|This group was deleted|8 hours|1 week|Always|Approve new members|Request sent. An admin will let you in.|Join requests|Approve|Report group|Report this group if it breaks Moments rules.",
"es": "%@ está escribiendo…|%@ y %@ están escribiendo…|Varias personas están escribiendo…|Buscar miembros|No se han encontrado miembros.|Mencionar a un miembro|%@ te ha mencionado|Descripción|Añade una descripción|Todos pueden enviar|Solo los admins pueden enviar|Solo los admins pueden enviar mensajes|Eliminar grupo|Se elimina el grupo para todos. Los mensajes ya descargados no se pueden borrar de sus dispositivos.|Se ha eliminado este grupo|8 horas|1 semana|Siempre|Aprobar a los nuevos miembros|Solicitud enviada. Un admin te dejará entrar.|Solicitudes para unirse|Aprobar|Reportar grupo|Reporta este grupo si incumple las normas de Moments.",
"ca": "%@ està escrivint…|%@ i %@ estan escrivint…|Diverses persones estan escrivint…|Cercar membres|No s’han trobat membres.|Mencionar un membre|%@ t’ha mencionat|Descripció|Afegeix una descripció|Tothom pot enviar|Només els admins poden enviar|Només els admins poden enviar missatges|Suprimir el grup|Se suprimeix el grup per a tothom. Els missatges ja descarregats no es poden esborrar dels seus dispositius.|S’ha suprimit aquest grup|8 hores|1 setmana|Sempre|Aprovar els membres nous|Sol·licitud enviada. Un admin et deixarà entrar.|Sol·licituds per unir-s’hi|Aprova|Denunciar el grup|Denuncia aquest grup si incompleix les normes de Moments.",
"de": "%@ schreibt…|%@ und %@ schreiben…|Mehrere Personen schreiben…|Mitglieder suchen|Keine Mitglieder gefunden.|Mitglied erwähnen|%@ hat dich erwähnt|Beschreibung|Beschreibung hinzufügen|Alle können senden|Nur Admins können senden|Nur Admins können Nachrichten senden|Gruppe löschen|Die Gruppe wird für alle gelöscht. Bereits heruntergeladene Nachrichten können nicht von den Geräten gelöscht werden.|Diese Gruppe wurde gelöscht|8 Stunden|1 Woche|Immer|Neue Mitglieder genehmigen|Anfrage gesendet. Ein Admin lässt dich rein.|Beitrittsanfragen|Genehmigen|Gruppe melden|Melde diese Gruppe, wenn sie gegen die Regeln von Moments verstößt.",
"fr": "%@ est en train d’écrire…|%@ et %@ sont en train d’écrire…|Plusieurs personnes écrivent…|Rechercher des membres|Aucun membre trouvé.|Mentionner un membre|%@ t’a mentionné|Description|Ajouter une description|Tout le monde peut envoyer|Seuls les admins peuvent envoyer|Seuls les admins peuvent envoyer des messages|Supprimer le groupe|Le groupe sera supprimé pour tout le monde. Les messages déjà téléchargés ne peuvent pas être effacés de leurs appareils.|Ce groupe a été supprimé|8 heures|1 semaine|Toujours|Approuver les nouveaux membres|Demande envoyée. Un admin te laissera entrer.|Demandes d’adhésion|Approuver|Signaler le groupe|Signale ce groupe s’il enfreint les règles de Moments.",
"it": "%@ sta scrivendo…|%@ e %@ stanno scrivendo…|Più persone stanno scrivendo…|Cerca membri|Nessun membro trovato.|Menziona un membro|%@ ti ha menzionato|Descrizione|Aggiungi una descrizione|Tutti possono inviare|Solo gli admin possono inviare|Solo gli admin possono inviare messaggi|Elimina gruppo|Il gruppo verrà eliminato per tutti. I messaggi già scaricati non possono essere cancellati dai loro dispositivi.|Questo gruppo è stato eliminato|8 ore|1 settimana|Sempre|Approva i nuovi membri|Richiesta inviata. Un admin ti farà entrare.|Richieste di ingresso|Approva|Segnala gruppo|Segnala questo gruppo se viola le regole di Moments.",
"pt-BR": "%@ está digitando…|%@ e %@ estão digitando…|Várias pessoas estão digitando…|Buscar membros|Nenhum membro encontrado.|Mencionar um membro|%@ mencionou você|Descrição|Adicione uma descrição|Todos podem enviar|Só admins podem enviar|Só admins podem enviar mensagens|Excluir grupo|O grupo será excluído para todos. Mensagens já baixadas não podem ser apagadas dos dispositivos.|Este grupo foi excluído|8 horas|1 semana|Sempre|Aprovar novos membros|Pedido enviado. Um admin vai deixar você entrar.|Pedidos para entrar|Aprovar|Denunciar grupo|Denuncie este grupo se ele violar as regras do Moments.",
"pt-PT": "%@ está a escrever…|%@ e %@ estão a escrever…|Várias pessoas estão a escrever…|Pesquisar membros|Nenhum membro encontrado.|Mencionar um membro|%@ mencionou-te|Descrição|Adiciona uma descrição|Toda a gente pode enviar|Só os admins podem enviar|Só os admins podem enviar mensagens|Eliminar grupo|O grupo será eliminado para todos. As mensagens já descarregadas não podem ser apagadas dos dispositivos.|Este grupo foi eliminado|8 horas|1 semana|Sempre|Aprovar novos membros|Pedido enviado. Um admin deixar-te-á entrar.|Pedidos para entrar|Aprovar|Denunciar grupo|Denuncia este grupo se violar as regras do Moments.",
"nl": "%@ typt…|%@ en %@ typen…|Meerdere mensen typen…|Leden zoeken|Geen leden gevonden.|Een lid vermelden|%@ heeft je genoemd|Beschrijving|Voeg een beschrijving toe|Iedereen kan sturen|Alleen admins kunnen sturen|Alleen admins kunnen berichten sturen|Groep verwijderen|De groep wordt voor iedereen verwijderd. Al gedownloade berichten kunnen niet van hun apparaten worden gewist.|Deze groep is verwijderd|8 uur|1 week|Altijd|Nieuwe leden goedkeuren|Verzoek verzonden. Een admin laat je binnen.|Deelnameverzoeken|Goedkeuren|Groep rapporteren|Rapporteer deze groep als die de regels van Moments overtreedt.",
"pl": "%@ pisze…|%@ i %@ piszą…|Kilka osób pisze…|Szukaj członków|Nie znaleziono członków.|Wspomnij członka|%@ wspomniał(a) o tobie|Opis|Dodaj opis|Wszyscy mogą wysyłać|Tylko admini mogą wysyłać|Tylko admini mogą wysyłać wiadomości|Usuń grupę|Grupa zostanie usunięta dla wszystkich. Pobranych wiadomości nie można usunąć z ich urządzeń.|Ta grupa została usunięta|8 godzin|1 tydzień|Zawsze|Zatwierdzaj nowych członków|Wysłano prośbę. Admin Cię wpuści.|Prośby o dołączenie|Zatwierdź|Zgłoś grupę|Zgłoś tę grupę, jeśli łamie zasady Moments.",
"ja": "%@さんが入力中…|%@さんと%@さんが入力中…|複数の人が入力中…|メンバーを検索|メンバーが見つかりません。|メンバーをメンション|%@さんがあなたをメンションしました|説明|説明を追加|全員が送信できる|管理者のみ送信できる|管理者のみメッセージを送信できます|グループを削除|グループは全員に対して削除されます。ダウンロード済みのメッセージを相手の端末から消すことはできません。|このグループは削除されました|8時間|1週間|常に|新しいメンバーを承認|リクエストを送信しました。管理者が参加を許可します。|参加リクエスト|承認|グループを報告|Momentsのルールに反する場合はこのグループを報告してください。",
"ko": "%@님이 입력 중…|%@님과 %@님이 입력 중…|여러 명이 입력 중…|멤버 검색|멤버를 찾을 수 없어요.|멤버 언급|%@님이 회원님을 언급했어요|설명|설명 추가|모두 보낼 수 있음|관리자만 보낼 수 있음|관리자만 메시지를 보낼 수 있어요|그룹 삭제|그룹이 모두에게서 삭제됩니다. 이미 다운로드한 메시지는 기기에서 지울 수 없어요.|이 그룹이 삭제되었어요|8시간|1주|항상|새 멤버 승인|요청을 보냈어요. 관리자가 들어오게 해 줄 거예요.|참여 요청|승인|그룹 신고|Moments 규칙을 어기면 이 그룹을 신고하세요.",
"zh-Hant": "%@正在輸入…|%@和%@正在輸入…|多人正在輸入…|搜尋成員|找不到成員。|提及成員|%@提及了你|說明|新增說明|所有人都可以傳送|僅管理員可以傳送|僅管理員可以傳送訊息|刪除群組|群組將對所有人刪除。已下載的訊息無法從對方裝置刪除。|此群組已刪除|8 小時|1 週|永遠|核准新成員|已送出請求。管理員會讓你加入。|加入請求|核准|檢舉群組|如果此群組違反 Moments 規範，請檢舉。",
"hi": "%@ टाइप कर रहे हैं…|%@ और %@ टाइप कर रहे हैं…|कई लोग टाइप कर रहे हैं…|सदस्य खोजें|कोई सदस्य नहीं मिला।|किसी सदस्य का उल्लेख करें|%@ ने आपका उल्लेख किया|विवरण|विवरण जोड़ें|सभी भेज सकते हैं|केवल एडमिन भेज सकते हैं|केवल एडमिन संदेश भेज सकते हैं|समूह हटाएँ|समूह सभी के लिए हट जाएगा। पहले से डाउनलोड किए गए संदेश उनके डिवाइस से नहीं मिटाए जा सकते।|यह समूह हटा दिया गया|8 घंटे|1 सप्ताह|हमेशा|नए सदस्यों को मंज़ूरी दें|अनुरोध भेजा गया। कोई एडमिन आपको अंदर आने देगा।|शामिल होने के अनुरोध|मंज़ूर करें|समूह रिपोर्ट करें|अगर यह समूह Moments के नियमों का उल्लंघन करता है तो रिपोर्ट करें।",
"id": "%@ sedang mengetik…|%@ dan %@ sedang mengetik…|Beberapa orang sedang mengetik…|Cari anggota|Tidak ada anggota ditemukan.|Sebut anggota|%@ menyebutmu|Deskripsi|Tambahkan deskripsi|Semua orang bisa mengirim|Hanya admin yang bisa mengirim|Hanya admin yang bisa mengirim pesan|Hapus grup|Grup akan dihapus untuk semua orang. Pesan yang sudah diunduh tidak dapat dihapus dari perangkat mereka.|Grup ini telah dihapus|8 jam|1 minggu|Selalu|Setujui anggota baru|Permintaan terkirim. Admin akan memasukkanmu.|Permintaan bergabung|Setujui|Laporkan grup|Laporkan grup ini jika melanggar aturan Moments.",
"tr": "%@ yazıyor…|%@ ve %@ yazıyor…|Birden fazla kişi yazıyor…|Üye ara|Üye bulunamadı.|Bir üyeden bahset|%@ senden bahsetti|Açıklama|Açıklama ekle|Herkes gönderebilir|Yalnızca yöneticiler gönderebilir|Yalnızca yöneticiler mesaj gönderebilir|Grubu sil|Grup herkes için silinir. Daha önce indirilen mesajlar cihazlarından silinemez.|Bu grup silindi|8 saat|1 hafta|Her zaman|Yeni üyeleri onayla|İstek gönderildi. Bir yönetici seni içeri alacak.|Katılma istekleri|Onayla|Grubu bildir|Moments kurallarını ihlal ediyorsa bu grubu bildir.",
}
qual = {'en': 'values', 'id': 'values-in', 'pt-BR': 'values-b+pt+BR', 'pt-PT': 'values-b+pt+PT', 'zh-Hant': 'values-b+zh+Hant'}

def resource(k):
    return 'groups_' + re.sub(r'(?<!^)(?=[A-Z])', '_', k).lower().replace('.', '_')

def android_value(value):
    n = 0
    def repl(_):
        nonlocal n
        n += 1
        return f'%{n}$s'
    return html.escape(re.sub(r'%@', repl, value), quote=False).replace("'", "\\'").replace('"', '\\"')

for lang, row in rows.items():
    values = row.split('|')
    if len(values) != len(keys):
        raise ValueError((lang, len(values), len(keys)))
    ios = ROOT / 'Moments/Moments' / f'{lang}.lproj' / 'Localizable.strings'
    text = ios.read_text()
    android = ROOT / 'MomentsAndroid/app/src/main/res' / qual.get(lang, 'values-' + lang) / 'strings_groups.xml'
    xml = android.read_text()
    for key, value in zip(keys, values):
        text = re.sub(r'^"groups\.' + re.escape(key) + r'" = .*;\n?', '', text, flags=re.M)
        text += '"groups.' + key + '" = ' + json.dumps(value, ensure_ascii=False) + ';\n'
        res = resource(key)
        xml = re.sub(r'\s*<string name="' + res + r'">.*?</string>', '', xml)
        xml = xml.replace('</resources>', f'    <string name="{res}">{android_value(value)}</string>\n</resources>')
    ios.write_text(text)
    android.write_text(xml)

p = ROOT / 'MomentsAndroid/app/src/main/java/com/moments/android/views/messaging/groups/GroupStrings.kt'
s = p.read_text()
for key in keys:
    if f'"{key}" ->' not in s:
        s = s.replace('    else ->', f'    "{key}" -> R.string.{resource(key)}\n    else ->')
p.write_text(s)
print('ok', len(keys), 'keys')
