/**
 * Correos de cuenta (verificar email y restablecer contraseña) en los 16 idiomas de la app.
 * render({ kind, locale, name, email, link }) → { subject, html, text }
 * Maquetación con tablas y estilos en línea para Gmail, Outlook y Apple Mail; modo oscuro donde el cliente lo soporta.
 */

const NBSP = ' ';
const ASSET_BASE = 'https://momentsapp.app/brand';

const STRINGS = {
  es: {
    verify: {
      subject: 'Confirma tu email en Moments',
      preheader: 'Un toque y tu cuenta queda lista.',
      title: 'Confirma tu email',
      body: 'Gracias por unirte a Moments. Confirma que este email es tuyo para proteger tu cuenta y poder recuperarla si algún día lo necesitas.',
      button: 'Confirmar email',
      ignore: 'Si no has creado una cuenta en Moments, ignora este correo.',
    },
    reset: {
      subject: 'Restablece tu contraseña de Moments',
      preheader: 'Elige una contraseña nueva en un minuto.',
      title: 'Restablece tu contraseña',
      body: 'Hemos recibido una solicitud para cambiar la contraseña de tu cuenta. Pulsa el botón para elegir una nueva.',
      button: 'Elegir contraseña nueva',
      expires: `Por seguridad, el enlace caduca en 1${NBSP}hora.`,
      ignore: 'Si no lo has pedido tú, ignora este correo: tu contraseña no cambiará.',
    },
    greeting: (name) => (name ? `Hola, ${name}` : 'Hola'),
    fallback: '¿El botón no funciona? Copia y pega este enlace en tu navegador:',
    sentTo: (email) => `Este correo se ha enviado a ${email}.`,
    help: 'Ayuda',
    privacy: 'Privacidad',
  },
  en: {
    verify: {
      subject: 'Confirm your email for Moments',
      preheader: 'One tap and your account is ready.',
      title: 'Confirm your email',
      body: 'Thanks for joining Moments. Confirm this email is yours to protect your account and recover it if you ever need to.',
      button: 'Confirm email',
      ignore: 'If you didn’t create a Moments account, you can ignore this email.',
    },
    reset: {
      subject: 'Reset your Moments password',
      preheader: 'Choose a new password in a minute.',
      title: 'Reset your password',
      body: 'We received a request to change your account password. Tap the button to choose a new one.',
      button: 'Choose new password',
      expires: `For your security, this link expires in 1${NBSP}hour.`,
      ignore: 'If you didn’t ask for this, ignore this email: your password won’t change.',
    },
    greeting: (name) => (name ? `Hi ${name},` : 'Hi,'),
    fallback: 'Button not working? Copy and paste this link into your browser:',
    sentTo: (email) => `This email was sent to ${email}.`,
    help: 'Help',
    privacy: 'Privacy',
  },
  ca: {
    verify: {
      subject: 'Confirma el teu correu a Moments',
      preheader: 'Un toc i el teu compte ja està a punt.',
      title: 'Confirma el teu correu',
      body: 'Gràcies per unir-te a Moments. Confirma que aquest correu és teu per protegir el compte i poder recuperar-lo si mai ho necessites.',
      button: 'Confirma el correu',
      ignore: 'Si no has creat cap compte a Moments, ignora aquest correu.',
    },
    reset: {
      subject: 'Restableix la contrasenya de Moments',
      preheader: 'Tria una contrasenya nova en un minut.',
      title: 'Restableix la contrasenya',
      body: 'Hem rebut una sol·licitud per canviar la contrasenya del teu compte. Prem el botó per triar-ne una de nova.',
      button: 'Tria una contrasenya nova',
      expires: `Per seguretat, l’enllaç caduca d’aquí a 1${NBSP}hora.`,
      ignore: 'Si no ho has demanat tu, ignora aquest correu: la contrasenya no canviarà.',
    },
    greeting: (name) => (name ? `Hola, ${name}` : 'Hola'),
    fallback: 'El botó no funciona? Copia i enganxa aquest enllaç al navegador:',
    sentTo: (email) => `Aquest correu s’ha enviat a ${email}.`,
    help: 'Ajuda',
    privacy: 'Privadesa',
  },
  de: {
    verify: {
      subject: 'Bestätige deine E-Mail für Moments',
      preheader: 'Ein Tipp und dein Konto ist bereit.',
      title: 'Bestätige deine E-Mail',
      body: 'Danke, dass du bei Moments bist. Bestätige, dass diese E-Mail dir gehört, damit dein Konto geschützt ist und du es bei Bedarf wiederherstellen kannst.',
      button: 'E-Mail bestätigen',
      ignore: 'Wenn du kein Moments-Konto erstellt hast, ignoriere diese E-Mail.',
    },
    reset: {
      subject: 'Setze dein Moments-Passwort zurück',
      preheader: 'Wähle in einer Minute ein neues Passwort.',
      title: 'Passwort zurücksetzen',
      body: 'Wir haben eine Anfrage erhalten, das Passwort deines Kontos zu ändern. Tippe auf den Button, um ein neues zu wählen.',
      button: 'Neues Passwort wählen',
      expires: `Aus Sicherheitsgründen läuft der Link in 1${NBSP}Stunde ab.`,
      ignore: 'Wenn du das nicht angefordert hast, ignoriere diese E-Mail: Dein Passwort bleibt unverändert.',
    },
    greeting: (name) => (name ? `Hallo ${name},` : 'Hallo,'),
    fallback: 'Der Button funktioniert nicht? Kopiere diesen Link in deinen Browser:',
    sentTo: (email) => `Diese E-Mail wurde an ${email} gesendet.`,
    help: 'Hilfe',
    privacy: 'Datenschutz',
  },
  fr: {
    verify: {
      subject: 'Confirme ton e-mail sur Moments',
      preheader: 'Un geste et ton compte est prêt.',
      title: 'Confirme ton e-mail',
      body: 'Merci d’avoir rejoint Moments. Confirme que cet e-mail t’appartient pour protéger ton compte et pouvoir le récupérer si besoin.',
      button: 'Confirmer l’e-mail',
      ignore: 'Si tu n’as pas créé de compte Moments, ignore cet e-mail.',
    },
    reset: {
      subject: 'Réinitialise ton mot de passe Moments',
      preheader: 'Choisis un nouveau mot de passe en une minute.',
      title: 'Réinitialise ton mot de passe',
      body: 'Nous avons reçu une demande de changement du mot de passe de ton compte. Appuie sur le bouton pour en choisir un nouveau.',
      button: 'Choisir un nouveau mot de passe',
      expires: `Par sécurité, ce lien expire dans 1${NBSP}heure.`,
      ignore: 'Si tu n’es pas à l’origine de cette demande, ignore cet e-mail : ton mot de passe ne changera pas.',
    },
    greeting: (name) => (name ? `Bonjour ${name},` : 'Bonjour,'),
    fallback: 'Le bouton ne fonctionne pas ? Copie et colle ce lien dans ton navigateur :',
    sentTo: (email) => `Cet e-mail a été envoyé à ${email}.`,
    help: 'Aide',
    privacy: 'Confidentialité',
  },
  hi: {
    verify: {
      subject: 'Moments के लिए अपने ईमेल की पुष्टि करें',
      preheader: 'एक टैप और आपका खाता तैयार।',
      title: 'अपने ईमेल की पुष्टि करें',
      body: 'Moments से जुड़ने के लिए धन्यवाद। पुष्टि करें कि यह ईमेल आपका है, ताकि आपका खाता सुरक्षित रहे और ज़रूरत पड़ने पर आप उसे वापस पा सकें।',
      button: 'ईमेल की पुष्टि करें',
      ignore: 'अगर आपने Moments पर खाता नहीं बनाया है, तो इस ईमेल को अनदेखा करें।',
    },
    reset: {
      subject: 'अपना Moments पासवर्ड रीसेट करें',
      preheader: 'एक मिनट में नया पासवर्ड चुनें।',
      title: 'अपना पासवर्ड रीसेट करें',
      body: 'हमें आपके खाते का पासवर्ड बदलने का अनुरोध मिला है। नया पासवर्ड चुनने के लिए बटन पर टैप करें।',
      button: 'नया पासवर्ड चुनें',
      expires: `सुरक्षा के लिए, यह लिंक 1${NBSP}घंटे में समाप्त हो जाएगा।`,
      ignore: 'अगर यह अनुरोध आपने नहीं किया है, तो इस ईमेल को अनदेखा करें: आपका पासवर्ड नहीं बदलेगा।',
    },
    greeting: (name) => (name ? `नमस्ते ${name},` : 'नमस्ते,'),
    fallback: 'बटन काम नहीं कर रहा? इस लिंक को कॉपी करके अपने ब्राउज़र में पेस्ट करें:',
    sentTo: (email) => `यह ईमेल ${email} पर भेजा गया था।`,
    help: 'सहायता',
    privacy: 'गोपनीयता',
  },
  id: {
    verify: {
      subject: 'Konfirmasi email kamu di Moments',
      preheader: 'Satu ketukan dan akunmu siap.',
      title: 'Konfirmasi email kamu',
      body: 'Terima kasih sudah bergabung dengan Moments. Konfirmasi bahwa email ini milikmu untuk melindungi akunmu dan memulihkannya jika suatu saat diperlukan.',
      button: 'Konfirmasi email',
      ignore: 'Jika kamu tidak membuat akun Moments, abaikan email ini.',
    },
    reset: {
      subject: 'Atur ulang kata sandi Moments kamu',
      preheader: 'Pilih kata sandi baru dalam semenit.',
      title: 'Atur ulang kata sandi',
      body: 'Kami menerima permintaan untuk mengubah kata sandi akunmu. Ketuk tombol untuk memilih kata sandi baru.',
      button: 'Pilih kata sandi baru',
      expires: `Demi keamanan, tautan ini kedaluwarsa dalam 1${NBSP}jam.`,
      ignore: 'Jika kamu tidak memintanya, abaikan email ini: kata sandimu tidak akan berubah.',
    },
    greeting: (name) => (name ? `Halo ${name},` : 'Halo,'),
    fallback: 'Tombol tidak berfungsi? Salin dan tempel tautan ini di browser kamu:',
    sentTo: (email) => `Email ini dikirim ke ${email}.`,
    help: 'Bantuan',
    privacy: 'Privasi',
  },
  it: {
    verify: {
      subject: 'Conferma la tua email su Moments',
      preheader: 'Un tocco e il tuo account è pronto.',
      title: 'Conferma la tua email',
      body: 'Grazie per esserti unito a Moments. Conferma che questa email è tua per proteggere il tuo account e poterlo recuperare se mai ti servisse.',
      button: 'Conferma email',
      ignore: 'Se non hai creato un account Moments, ignora questa email.',
    },
    reset: {
      subject: 'Reimposta la password di Moments',
      preheader: 'Scegli una nuova password in un minuto.',
      title: 'Reimposta la password',
      body: 'Abbiamo ricevuto una richiesta per cambiare la password del tuo account. Tocca il pulsante per sceglierne una nuova.',
      button: 'Scegli una nuova password',
      expires: `Per sicurezza, il link scade tra 1${NBSP}ora.`,
      ignore: 'Se non l’hai chiesto tu, ignora questa email: la tua password non cambierà.',
    },
    greeting: (name) => (name ? `Ciao ${name},` : 'Ciao,'),
    fallback: 'Il pulsante non funziona? Copia e incolla questo link nel browser:',
    sentTo: (email) => `Questa email è stata inviata a ${email}.`,
    help: 'Aiuto',
    privacy: 'Privacy',
  },
  ja: {
    verify: {
      subject: 'Momentsのメールアドレスを確認してください',
      preheader: 'タップするだけでアカウントの準備が完了します。',
      title: 'メールアドレスの確認',
      body: 'Momentsにご登録いただきありがとうございます。このメールアドレスがご本人のものであることを確認すると、アカウントが保護され、必要なときに復元できるようになります。',
      button: 'メールアドレスを確認',
      ignore: 'Momentsのアカウントを作成した覚えがない場合は、このメールを無視してください。',
    },
    reset: {
      subject: 'Momentsのパスワードを再設定',
      preheader: '1分で新しいパスワードを設定できます。',
      title: 'パスワードの再設定',
      body: 'アカウントのパスワード変更のリクエストを受け付けました。ボタンをタップして新しいパスワードを設定してください。',
      button: '新しいパスワードを設定',
      expires: `セキュリティのため、このリンクの有効期限は1${NBSP}時間です。`,
      ignore: 'このリクエストに心当たりがない場合は、このメールを無視してください。パスワードは変更されません。',
    },
    greeting: (name) => (name ? `${name}さん、こんにちは` : 'こんにちは'),
    fallback: 'ボタンが機能しない場合は、このリンクをコピーしてブラウザに貼り付けてください：',
    sentTo: (email) => `このメールは${email}宛てに送信されました。`,
    help: 'ヘルプ',
    privacy: 'プライバシー',
  },
  ko: {
    verify: {
      subject: 'Moments 이메일을 확인해 주세요',
      preheader: '한 번만 탭하면 계정 준비 완료.',
      title: '이메일 확인',
      body: 'Moments에 가입해 주셔서 감사해요. 이 이메일이 본인 것임을 확인하면 계정을 보호하고 필요할 때 복구할 수 있어요.',
      button: '이메일 확인',
      ignore: 'Moments 계정을 만들지 않았다면 이 이메일을 무시하세요.',
    },
    reset: {
      subject: 'Moments 비밀번호 재설정',
      preheader: '1분이면 새 비밀번호를 설정할 수 있어요.',
      title: '비밀번호 재설정',
      body: '계정 비밀번호 변경 요청을 받았어요. 버튼을 탭해서 새 비밀번호를 설정하세요.',
      button: '새 비밀번호 설정',
      expires: `보안을 위해 이 링크는 1${NBSP}시간 후에 만료돼요.`,
      ignore: '직접 요청하지 않았다면 이 이메일을 무시하세요. 비밀번호는 바뀌지 않아요.',
    },
    greeting: (name) => (name ? `${name}님, 안녕하세요` : '안녕하세요'),
    fallback: '버튼이 작동하지 않나요? 이 링크를 복사해 브라우저에 붙여 넣으세요:',
    sentTo: (email) => `이 이메일은 ${email}(으)로 발송되었어요.`,
    help: '도움말',
    privacy: '개인정보 보호',
  },
  nl: {
    verify: {
      subject: 'Bevestig je e-mail voor Moments',
      preheader: 'Eén tik en je account is klaar.',
      title: 'Bevestig je e-mail',
      body: 'Bedankt dat je lid bent geworden van Moments. Bevestig dat dit e-mailadres van jou is, zodat je account beschermd is en je het kunt herstellen als dat ooit nodig is.',
      button: 'E-mail bevestigen',
      ignore: 'Heb je geen Moments-account aangemaakt? Dan kun je deze e-mail negeren.',
    },
    reset: {
      subject: 'Stel je Moments-wachtwoord opnieuw in',
      preheader: 'Kies binnen een minuut een nieuw wachtwoord.',
      title: 'Wachtwoord opnieuw instellen',
      body: 'We hebben een verzoek ontvangen om het wachtwoord van je account te wijzigen. Tik op de knop om een nieuw wachtwoord te kiezen.',
      button: 'Nieuw wachtwoord kiezen',
      expires: `Voor je veiligheid verloopt deze link over 1${NBSP}uur.`,
      ignore: 'Heb je dit niet aangevraagd? Negeer deze e-mail: je wachtwoord blijft hetzelfde.',
    },
    greeting: (name) => (name ? `Hoi ${name},` : 'Hoi,'),
    fallback: 'Werkt de knop niet? Kopieer deze link en plak hem in je browser:',
    sentTo: (email) => `Deze e-mail is verstuurd naar ${email}.`,
    help: 'Help',
    privacy: 'Privacy',
  },
  pl: {
    verify: {
      subject: 'Potwierdź swój e-mail w Moments',
      preheader: 'Jedno dotknięcie i Twoje konto jest gotowe.',
      title: 'Potwierdź swój e-mail',
      body: 'Dziękujemy za dołączenie do Moments. Potwierdź, że ten e-mail należy do Ciebie, aby chronić konto i móc je odzyskać, gdyby kiedyś było to potrzebne.',
      button: 'Potwierdź e-mail',
      ignore: 'Jeśli nie zakładałeś konta w Moments, zignoruj tę wiadomość.',
    },
    reset: {
      subject: 'Zresetuj hasło do Moments',
      preheader: 'Wybierz nowe hasło w minutę.',
      title: 'Zresetuj hasło',
      body: 'Otrzymaliśmy prośbę o zmianę hasła do Twojego konta. Dotknij przycisku, aby wybrać nowe.',
      button: 'Wybierz nowe hasło',
      expires: `Ze względów bezpieczeństwa link wygaśnie za 1${NBSP}godzinę.`,
      ignore: 'Jeśli to nie Ty, zignoruj tę wiadomość: Twoje hasło się nie zmieni.',
    },
    greeting: (name) => (name ? `Cześć ${name},` : 'Cześć,'),
    fallback: 'Przycisk nie działa? Skopiuj ten link i wklej go w przeglądarce:',
    sentTo: (email) => `Ta wiadomość została wysłana na adres ${email}.`,
    help: 'Pomoc',
    privacy: 'Prywatność',
  },
  'pt-BR': {
    verify: {
      subject: 'Confirme seu e-mail no Moments',
      preheader: 'Um toque e sua conta fica pronta.',
      title: 'Confirme seu e-mail',
      body: 'Obrigado por entrar no Moments. Confirme que este e-mail é seu para proteger sua conta e poder recuperá-la se um dia precisar.',
      button: 'Confirmar e-mail',
      ignore: 'Se você não criou uma conta no Moments, ignore este e-mail.',
    },
    reset: {
      subject: 'Redefina sua senha do Moments',
      preheader: 'Escolha uma nova senha em um minuto.',
      title: 'Redefina sua senha',
      body: 'Recebemos um pedido para alterar a senha da sua conta. Toque no botão para escolher uma nova.',
      button: 'Escolher nova senha',
      expires: `Por segurança, o link expira em 1${NBSP}hora.`,
      ignore: 'Se não foi você quem pediu, ignore este e-mail: sua senha não vai mudar.',
    },
    greeting: (name) => (name ? `Oi, ${name}` : 'Oi'),
    fallback: 'O botão não funciona? Copie e cole este link no seu navegador:',
    sentTo: (email) => `Este e-mail foi enviado para ${email}.`,
    help: 'Ajuda',
    privacy: 'Privacidade',
  },
  'pt-PT': {
    verify: {
      subject: 'Confirma o teu email no Moments',
      preheader: 'Um toque e a tua conta fica pronta.',
      title: 'Confirma o teu email',
      body: 'Obrigado por te juntares ao Moments. Confirma que este email é teu para proteger a tua conta e poderes recuperá-la se algum dia precisares.',
      button: 'Confirmar email',
      ignore: 'Se não criaste uma conta no Moments, ignora este email.',
    },
    reset: {
      subject: 'Repõe a tua palavra-passe do Moments',
      preheader: 'Escolhe uma nova palavra-passe num minuto.',
      title: 'Repõe a tua palavra-passe',
      body: 'Recebemos um pedido para alterar a palavra-passe da tua conta. Toca no botão para escolheres uma nova.',
      button: 'Escolher nova palavra-passe',
      expires: `Por segurança, a ligação expira dentro de 1${NBSP}hora.`,
      ignore: 'Se não foste tu a pedir, ignora este email: a tua palavra-passe não vai mudar.',
    },
    greeting: (name) => (name ? `Olá, ${name}` : 'Olá'),
    fallback: 'O botão não funciona? Copia e cola esta ligação no teu navegador:',
    sentTo: (email) => `Este email foi enviado para ${email}.`,
    help: 'Ajuda',
    privacy: 'Privacidade',
  },
  tr: {
    verify: {
      subject: 'Moments e-postanı onayla',
      preheader: 'Tek dokunuşla hesabın hazır.',
      title: 'E-postanı onayla',
      body: 'Moments’a katıldığın için teşekkürler. Hesabını korumak ve gerekirse kurtarabilmek için bu e-postanın sana ait olduğunu onayla.',
      button: 'E-postayı onayla',
      ignore: 'Moments hesabı oluşturmadıysan bu e-postayı yok sayabilirsin.',
    },
    reset: {
      subject: 'Moments şifreni sıfırla',
      preheader: 'Bir dakikada yeni bir şifre belirle.',
      title: 'Şifreni sıfırla',
      body: 'Hesabının şifresini değiştirmek için bir istek aldık. Yeni bir şifre belirlemek için düğmeye dokun.',
      button: 'Yeni şifre belirle',
      expires: `Güvenliğin için bu bağlantının süresi 1${NBSP}saat içinde dolacak.`,
      ignore: 'Bu isteği sen yapmadıysan bu e-postayı yok say: şifren değişmeyecek.',
    },
    greeting: (name) => (name ? `Merhaba ${name},` : 'Merhaba,'),
    fallback: 'Düğme çalışmıyor mu? Bu bağlantıyı kopyalayıp tarayıcına yapıştır:',
    sentTo: (email) => `Bu e-posta ${email} adresine gönderildi.`,
    help: 'Yardım',
    privacy: 'Gizlilik',
  },
  'zh-Hant': {
    verify: {
      subject: '確認你的 Moments 電子郵件',
      preheader: '輕點一下，帳號就準備好了。',
      title: '確認你的電子郵件',
      body: '感謝你加入 Moments。確認這個電子郵件屬於你，可以保護你的帳號，並在需要時用來找回帳號。',
      button: '確認電子郵件',
      ignore: '如果你沒有建立 Moments 帳號，請忽略這封郵件。',
    },
    reset: {
      subject: '重設你的 Moments 密碼',
      preheader: '一分鐘就能設定新密碼。',
      title: '重設密碼',
      body: '我們收到變更你帳號密碼的要求。請點選按鈕設定新密碼。',
      button: '設定新密碼',
      expires: `為了安全，此連結將在 1${NBSP}小時後失效。`,
      ignore: '如果這不是你提出的要求，請忽略這封郵件，你的密碼不會變更。',
    },
    greeting: (name) => (name ? `${name}，你好` : '你好'),
    fallback: '按鈕無法使用？請複製此連結並貼到瀏覽器中：',
    sentTo: (email) => `這封郵件寄送至 ${email}。`,
    help: '說明',
    privacy: '隱私權',
  },
};

const LOCALES = Object.keys(STRINGS);

/** Normaliza el idioma que manda la app ("pt_BR", "zh-Hant-TW", "in"…) a uno de los 16. */
function resolveLocale(raw) {
  const value = String(raw || '').replace('_', '-').trim();
  const lower = value.toLowerCase();
  if (STRINGS[value]) return value;
  if (lower.startsWith('zh')) return 'zh-Hant';
  if (lower === 'pt-br') return 'pt-BR';
  if (lower.startsWith('pt')) return 'pt-PT';
  if (lower === 'in' || lower.startsWith('id')) return 'id';
  const base = lower.split('-')[0];
  return STRINGS[base] ? base : 'en';
}

const C = {
  bg: '#FAF9F6',
  card: '#FFFFFF',
  cardLine: '#ECEBE7',
  ink: '#0B1215',
  text: '#4F5659',
  muted: '#868C8F',
  button: '#0B1215',
  buttonInk: '#FAF9F6',
  line: '#EEEDEA',
};

const FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";
const DISPLAY = "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', Roboto, Helvetica, Arial, sans-serif";

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
/** Escapa y protege el nombre de la marca frente al traductor automático del cliente de correo. */
const copy = (s) => esc(s).replace(/Moments/g, '<span translate="no">Moments</span>');

function render({ kind, locale, name = '', email, link }) {
  const lang = resolveLocale(locale);
  const L = STRINGS[lang];
  const T = L[kind];
  if (!T) throw new Error(`Unknown email kind: ${kind}`);
  const href = esc(link);
  const logo = `${ASSET_BASE}/logotipo-morado.png`;
  const logoDark = `${ASSET_BASE}/logotipo-blanco.png`;
  const iso = `${ASSET_BASE}/isotipo-morado.png`;
  const isoDark = `${ASSET_BASE}/isotipo-blanco.png`;
  const expires = T.expires
    ? `<p class="muted" style="margin:18px 0 0;font:500 14px/1.5 ${FONT};color:${C.muted};">${copy(T.expires)}</p>`
    : '';

  const html = `<!doctype html>
<html lang="${esc(lang)}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark">
<title>${esc(T.subject)}</title>
<style>
  h1 { text-wrap: balance; word-break: auto-phrase; }
  @media (prefers-color-scheme: dark) {
    .bg { background:#0B1215 !important; }
    .card { background:#11191D !important; border-color:#1E272B !important; box-shadow:none !important; }
    .ink { color:#FAF9F6 !important; }
    .txt { color:#BFC4C6 !important; }
    .muted { color:#8A9194 !important; }
    .line { border-color:#1E272B !important; }
    .fallback-link { color:#BFC4C6 !important; }
    .btn { background:#FAF9F6 !important; }
    .btn a, .btn span { color:#0B1215 !important; }
    .btn-dot { background:rgba(11,18,21,0.10) !important; }
    .logo-light { display:none !important; }
    .logo-dark { display:block !important; max-height:none !important; }
  }
  @media (max-width:520px) { .pad { padding:36px 26px 32px !important; } }
</style>
</head>
<body style="margin:0;padding:0;background:${C.bg};" class="bg">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${esc(T.preheader)}</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" class="bg" style="background:${C.bg};">
  <tr><td align="center" style="padding:44px 14px 40px;">
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:528px;">
      <tr><td align="center" style="padding:0 0 30px;">
        <img class="logo-light" src="${logo}" width="160" alt="Moments" style="display:block;width:160px;height:auto;border:0;">
        <!--[if !mso]><!--><img class="logo-dark" src="${logoDark}" width="160" alt="Moments" style="display:none;width:160px;height:auto;border:0;max-height:0;overflow:hidden;"><!--<![endif]-->
      </td></tr>
      <tr><td>
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
          <tr><td class="card pad" style="background:${C.card};border:1px solid ${C.cardLine};border-radius:28px;padding:44px 44px 38px;box-shadow:0 1px 2px rgba(11,18,21,0.04),0 18px 40px -20px rgba(11,18,21,0.12);">
            <p class="txt" style="margin:0 0 8px;font:500 16px/1.4 ${FONT};color:${C.text};">${esc(L.greeting(name))}</p>
            <h1 class="ink" style="margin:0 0 16px;font:700 30px/1.15 ${DISPLAY};color:${C.ink};letter-spacing:-0.5px;">${copy(T.title)}</h1>
            <p class="txt" style="margin:0 0 32px;font:400 16px/1.6 ${FONT};color:${C.text};max-width:420px;">${copy(T.body)}</p>
            <table role="presentation" cellspacing="0" cellpadding="0" border="0"><tr>
              <td class="btn" style="background:${C.button};border-radius:999px;">
                <a href="${href}" style="display:block;padding:7px 7px 7px 28px;text-decoration:none;border-radius:999px;">
                  <table role="presentation" cellspacing="0" cellpadding="0" border="0"><tr>
                    <td style="font:600 17px/1 ${FONT};color:${C.buttonInk};padding-right:16px;white-space:nowrap;"><span style="color:${C.buttonInk};">${esc(T.button)}</span></td>
                    <td class="btn-dot" width="38" height="38" align="center" style="width:38px;height:38px;border-radius:999px;background:rgba(250,249,246,0.16);font:600 18px/38px ${FONT};color:${C.buttonInk};"><span style="color:${C.buttonInk};">&rarr;</span></td>
                  </tr></table>
                </a>
              </td>
            </tr></table>
            ${expires}
            <p class="txt" style="margin:30px 0 0;font:400 15px/1.6 ${FONT};color:${C.text};">${copy(T.ignore)}</p>
            <div class="line" style="margin:30px 0 0;padding:22px 0 0;border-top:1px solid ${C.line};">
              <p class="muted" style="margin:0 0 6px;font:400 13px/1.5 ${FONT};color:${C.muted};">${esc(L.fallback)}</p>
              <p style="margin:0;font:400 13px/1.5 ${FONT};word-break:break-all;"><a class="fallback-link" href="${href}" style="color:${C.text};text-decoration:underline;">${href}</a></p>
            </div>
          </td></tr>
        </table>
      </td></tr>
      <tr><td align="center" style="padding:30px 24px 0;">
        <p class="muted" style="margin:0 0 10px;font:400 13px/1.5 ${FONT};color:${C.muted};">${esc(L.sentTo(email))}</p>
        <p style="margin:0;font:500 13px/1.5 ${FONT};">
          <a class="muted" href="https://momentsapp.app/help" style="color:${C.muted};text-decoration:underline;">${esc(L.help)}</a>
          <span class="muted" style="color:${C.muted};">&nbsp;&middot;&nbsp;</span>
          <a class="muted" href="https://momentsapp.app/privacy" style="color:${C.muted};text-decoration:underline;">${esc(L.privacy)}</a>
        </p>
        <a href="https://momentsapp.app" style="display:inline-block;margin:18px 0 0;text-decoration:none;">
          <img class="logo-light" src="${iso}" width="40" alt="Moments" style="display:block;width:40px;height:auto;border:0;">
          <!--[if !mso]><!--><img class="logo-dark" src="${isoDark}" width="40" alt="Moments" style="display:none;width:40px;height:auto;border:0;max-height:0;overflow:hidden;"><!--<![endif]-->
        </a>
      </td></tr>
    </table>
  </td></tr>
</table>
</body>
</html>`;

  const text = [
    L.greeting(name), '', T.title, '', T.body, '',
    `${T.button}: ${link}`, T.expires || '', '', T.ignore, '',
    L.sentTo(email), `${L.help}: https://momentsapp.app/help`,
  ].filter((l, i, a) => !(l === '' && a[i - 1] === '')).join('\n');

  return { subject: T.subject, html, text, locale: lang };
}

module.exports = { render, resolveLocale, LOCALES };
