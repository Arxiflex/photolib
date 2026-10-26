// The page at photolibd's address, which a password setup link opens until photolibd serves the web app (ADR-0243):
// it hands the link to the app through the photolib: scheme every app registers, and says how to paste it into the app
// otherwise. The token stays in the fragment, which reaches no server.
'use strict';

// Every language the apps launch in (docs/dev/translations.md), with the app's own words for Settings and Add a server.
const TEXT = {
  en: ['Open in Photolib', 'In the Photolib app, open Settings, choose “Add a server” and paste the address of this page.'],
  es: ['Abrir en Photolib', 'En la app Photolib, abre Configuración, elige «Añadir un servidor» y pega la dirección de esta página.'],
  fr: ['Ouvrir dans Photolib', 'Dans l’app Photolib, ouvrez Paramètres, choisissez « Ajouter un serveur » et collez l’adresse de cette page.'],
  de: ['In Photolib öffnen', 'Öffne in der Photolib-App die Einstellungen, wähle „Server hinzufügen“ und füge die Adresse dieser Seite ein.'],
  it: ['Apri in Photolib', 'Nell’app Photolib apri Impostazioni, scegli «Aggiungi un server» e incolla l’indirizzo di questa pagina.'],
  pt: ['Abrir no Photolib', 'No app Photolib, abra Configurações, escolha “Adicionar um servidor” e cole o endereço desta página.'],
  ru: ['Открыть в Photolib', 'В приложении Photolib откройте Настройки, выберите «Добавить сервер» и вставьте адрес этой страницы.'],
  uk: ['Відкрити в Photolib', 'У застосунку Photolib відкрийте Налаштування, виберіть «Додати сервер» і вставте адресу цієї сторінки.'],
  pl: ['Otwórz w Photolib', 'W aplikacji Photolib otwórz Ustawienia, wybierz „Dodaj serwer” i wklej adres tej strony.'],
  nl: ['Openen in Photolib', 'Open in de Photolib-app Instellingen, kies ‘Server toevoegen’ en plak het adres van deze pagina.'],
  tr: ['Photolib’de aç', 'Photolib uygulamasında Ayarlar’ı açın, “Sunucu ekle”yi seçin ve bu sayfanın adresini yapıştırın.'],
  ar: ['فتح في Photolib', 'في تطبيق Photolib، افتح الإعدادات، واختر «إضافة خادم»، والصق عنوان هذه الصفحة.'],
  he: ['פתיחה ב־Photolib', 'באפליקציית Photolib, פתחו את הגדרות, בחרו „הוספת שרת” והדביקו את הכתובת של הדף הזה.'],
  hi: ['Photolib में खोलें', 'Photolib ऐप में सेटिंग खोलें, “सर्वर जोड़ें” चुनें और इस पेज का पता पेस्ट करें।'],
  ja: ['Photolib で開く', 'Photolib アプリで設定を開き、「サーバーを追加」を選んで、このページのアドレスを貼り付けてください。'],
  ko: ['Photolib에서 열기', 'Photolib 앱에서 설정을 열고 ‘서버 추가’를 선택한 다음 이 페이지의 주소를 붙여 넣으세요.'],
  zh: ['在 Photolib 中打开', '在 Photolib 应用中打开“设置”，选择“添加服务器”，然后粘贴此页面的地址。'],
  'zh-Hant': ['在 Photolib 中開啟', '在 Photolib App 中開啟「設定」，選擇「新增伺服器」，然後貼上此頁面的網址。'],
  id: ['Buka di Photolib', 'Di aplikasi Photolib, buka Setelan, pilih “Tambahkan server”, lalu tempel alamat halaman ini.'],
  vi: ['Mở trong Photolib', 'Trong ứng dụng Photolib, mở Cài đặt, chọn “Thêm máy chủ” rồi dán địa chỉ của trang này.'],
  sv: ['Öppna i Photolib', 'Öppna Inställningar i Photolib-appen, välj ”Lägg till en server” och klistra in adressen till den här sidan.'],
};

// The first of the browser's languages that the page speaks, else English; Traditional Chinese by script or region.
function language(tags) {
  for (const tag of tags) {
    const [base, ...rest] = tag.toLowerCase().split('-');
    const code = base === 'zh' && rest.some((part) => ['hant', 'tw', 'hk', 'mo'].includes(part)) ? 'zh-Hant' : base;
    if (Object.hasOwn(TEXT, code)) return code;
  }
  return 'en';
}

// `photolib:/password-setup?server=…&handle=…&token=…` for a page opened at `<server>#/password-setup?handle=…&token=…`.
function appLink(href) {
  const page = new URL(href);
  const [route, query] = page.hash.slice(1).split('?');
  const setup = new URLSearchParams(query);
  if (route !== '/password-setup' || !setup.get('handle') || !setup.get('token')) return null;
  page.hash = '';
  page.search = '';
  const link = new URL('photolib:/password-setup');
  link.search = new URLSearchParams({ handle: setup.get('handle'), token: setup.get('token'), server: page.href });
  return link.href;
}

if (typeof document === 'object') {
  const code = language(navigator.languages);
  const [open, paste] = TEXT[code];
  document.documentElement.lang = code;
  document.documentElement.dir = ['ar', 'he'].includes(code) ? 'rtl' : 'ltr';
  document.getElementById('paste').textContent = paste;
  const link = appLink(location.href);
  if (link) {
    const button = document.getElementById('open');
    button.href = link;
    button.textContent = open;
    button.hidden = false;
  }
}
if (typeof module === 'object') module.exports = { TEXT, appLink, language };
