import React, { useState } from 'react';
import { Shield, Lock, Eye, Users, MessageCircle, Settings, Mail, Globe, Check, Globe2 } from 'lucide-react';

const PrivacyPolicy = () => {
  const [language, setLanguage] = useState('es');

  const translations = {
    es: {
      title: "Políticas de Privacidad",
      subtitle: "Tu privacidad es nuestra prioridad. Conoce cómo protegemos y manejamos tu información personal.",
      lastUpdate: "Última actualización: 12 de agosto de 2025",
      introduction: {
        title: "Introducción",
        content: "Bienvenido a Moments. Nos comprometemos a proteger tu privacidad y a garantizar que tus datos personales sean manejados de manera segura y responsable. Esta política describe cómo recopilamos, usamos y protegemos tu información, incluyendo tu interacción con Nova, tu asistente personal."
      },
      dataCollection: {
        title: "Datos que Recopilamos",
        subtitle: "Recopilamos la siguiente información cuando te registras o usas Moments:",
        items: [
          { title: "Datos de Registro", desc: "Nombre de usuario, correo electrónico y contraseña." },
          { title: "Datos de Perfil", desc: "Intereses, publicaciones, conexiones y preferencias." },
          { title: "Datos de Uso", desc: "Interacciones en la app, como visitas a perfiles y mensajes." },
          { title: "Interacciones con Nova", desc: "Conversaciones, preferencias personalizadas y datos contextuales." }
        ]
      },
      nova: {
        title: "Nova - Tu Asistente Personal",
        subtitle: "Nova es tu asistente IA personal en Moments. Para brindarte una experiencia personalizada:",
        items: [
          { title: "Memoria Contextual", desc: "Nova recuerda información que compartes para personalizar sus respuestas." },
          { title: "Privacidad de Nova", desc: "Las conversaciones con Nova son privadas y encriptadas." },
          { title: "Control Total", desc: "Puedes eliminar la memoria de Nova en cualquier momento." },
          { title: "Sin Compartir", desc: "Los datos de Nova nunca se comparten con terceros." }
        ]
      },
      dataUsage: {
        title: "Uso de los Datos",
        neverSell: "Nunca vendemos tus datos a terceros",
        items: [
          "Proporcionar y personalizar tu experiencia en Moments",
          "Permitir que Nova te ofrezca asistencia personalizada y contextual",
          "Conectar con otros usuarios según tus intereses",
          "Enviar notificaciones y comunicaciones relevantes",
          "Mejorar nuestros servicios y garantizar la seguridad"
        ]
      },
      security: {
        title: "Almacenamiento y Seguridad",
        subtitle: "Tus datos se almacenan en servidores seguros gestionados por Firebase. Implementamos:",
        items: [
          { title: "Encriptación End-to-End", desc: "Para datos sensibles y conversaciones con Nova" },
          { title: "Encriptación en Reposo", desc: "Todos los datos almacenados están encriptados" },
          { title: "Acceso Restringido", desc: "Solo personal autorizado con necesidad legítima" },
          { title: "Auditorías Regulares", desc: "Revisiones de seguridad periódicas" }
        ]
      },
      rights: {
        title: "Tus Derechos",
        subtitle: "Tienes derecho a:",
        items: [
          "Acceder a todos tus datos, incluyendo el historial con Nova",
          "Corregir información incorrecta",
          "Eliminar tu cuenta y todos los datos asociados",
          "Exportar tus datos en formato estándar (JSON/CSV)",
          "Resetear la memoria de Nova",
          "Controlar la visibilidad de tu contenido",
          "Desactivar notificaciones y comunicaciones"
        ]
      },
      contact: {
        title: "Contacto",
        subtitle: "Si tienes preguntas sobre esta política o sobre cómo protegemos tu privacidad:",
        email: "support@momentsapp.app",
        assistant: "Pregúntale a Nova",
        web: "momentsapp.app"
      },
      commitment: {
        title: "Compromiso Final",
        subtitle: "En Moments, creemos que la privacidad es un derecho fundamental. Nuestro compromiso:",
        items: [
          "Tu contenido, tus reglas",
          "Tus datos nunca se venden",
          "Transparencia total",
          "Control absoluto",
          "Nova respeta tu privacidad"
        ],
        quote: "Cada momento es tuyo. Tu privacidad también."
      },
      footer: {
        copyright: "© 2025 Moments - Red Social Centrada en Privacidad",
        website: "momentsapp.app"
      }
    },
    en: {
      title: "Privacy Policy",
      subtitle: "Your privacy is our priority. Learn how we protect and handle your personal information.",
      lastUpdate: "Last updated: August 12, 2025",
      introduction: {
        title: "Introduction",
        content: "Welcome to Moments. We are committed to protecting your privacy and ensuring that your personal data is handled safely and responsibly. This policy describes how we collect, use and protect your information, including your interaction with Nova, your personal assistant."
      },
      dataCollection: {
        title: "Data We Collect",
        subtitle: "We collect the following information when you register or use Moments:",
        items: [
          { title: "Registration Data", desc: "Username, email and password." },
          { title: "Profile Data", desc: "Interests, posts, connections and preferences." },
          { title: "Usage Data", desc: "App interactions, such as profile visits and messages." },
          { title: "Nova Interactions", desc: "Conversations, personalized preferences and contextual data." }
        ]
      },
      nova: {
        title: "Nova - Your Personal Assistant",
        subtitle: "Nova is your personal AI assistant in Moments. To provide you with a personalized experience:",
        items: [
          { title: "Contextual Memory", desc: "Nova remembers information you share to personalize her responses." },
          { title: "Nova Privacy", desc: "Conversations with Nova are private and encrypted." },
          { title: "Total Control", desc: "You can delete Nova's memory at any time." },
          { title: "No Sharing", desc: "Nova's data is never shared with third parties." }
        ]
      },
      dataUsage: {
        title: "Data Usage",
        neverSell: "We never sell your data to third parties",
        items: [
          "Provide and personalize your experience in Moments",
          "Allow Nova to offer you personalized and contextual assistance",
          "Connect with other users based on your interests",
          "Send relevant notifications and communications",
          "Improve our services and ensure security"
        ]
      },
      security: {
        title: "Storage and Security",
        subtitle: "Your data is stored on secure servers managed by Firebase. We implement:",
        items: [
          { title: "End-to-End Encryption", desc: "For sensitive data and conversations with Nova" },
          { title: "Encryption at Rest", desc: "All stored data is encrypted" },
          { title: "Restricted Access", desc: "Only authorized personnel with legitimate need" },
          { title: "Regular Audits", desc: "Periodic security reviews" }
        ]
      },
      rights: {
        title: "Your Rights",
        subtitle: "You have the right to:",
        items: [
          "Access all your data, including history with Nova",
          "Correct incorrect information",
          "Delete your account and all associated data",
          "Export your data in standard format (JSON/CSV)",
          "Reset Nova's memory",
          "Control the visibility of your content",
          "Disable notifications and communications"
        ]
      },
      contact: {
        title: "Contact",
        subtitle: "If you have questions about this policy or how we protect your privacy:",
        email: "support@momentsapp.app",
        assistant: "Ask Nova",
        web: "momentsapp.app"
      },
      commitment: {
        title: "Final Commitment",
        subtitle: "At Moments, we believe privacy is a fundamental right. Our commitment:",
        items: [
          "Your content, your rules",
          "Your data is never sold",
          "Total transparency",
          "Absolute control",
          "Nova respects your privacy"
        ],
        quote: "Every moment is yours. Your privacy too."
      },
      footer: {
        copyright: "© 2025 Moments - Privacy-Focused Social Network",
        website: "momentsapp.app"
      }
    },
    ca: {
      title: "Polítiques de Privacitat",
      subtitle: "La teva privacitat és la nostra prioritat. Descobreix com protegim i gestionem la teva informació personal.",
      lastUpdate: "Última actualització: 12 d'agost de 2025",
      introduction: {
        title: "Introducció",
        content: "Benvingut a Moments. Ens comprometem a protegir la teva privacitat i a garantir que les teves dades personals siguin gestionades de manera segura i responsable. Aquesta política descriu com recopilem, utilitzem i protegim la teva informació, incloent la teva interacció amb Nova, la teva assistent personal."
      },
      dataCollection: {
        title: "Dades que Recopilem",
        subtitle: "Recopilem la següent informació quan et registres o utilitzes Moments:",
        items: [
          { title: "Dades de Registre", desc: "Nom d'usuari, correu electrònic i contrasenya." },
          { title: "Dades de Perfil", desc: "Interessos, publicacions, connexions i preferències." },
          { title: "Dades d'Ús", desc: "Interaccions a l'app, com visites a perfils i missatges." },
          { title: "Interaccions amb Nova", desc: "Converses, preferències personalitzades i dades contextuals." }
        ]
      },
      nova: {
        title: "Nova - La Teva Assistenta Personal",
        subtitle: "Nova és la teva assistenta IA personal a Moments. Per oferir-te una experiència personalitzada:",
        items: [
          { title: "Memòria Contextual", desc: "Nova recorda informació que comparteixes per personalitzar les seves respostes." },
          { title: "Privacitat de Nova", desc: "Les converses amb Nova són privades i encriptades." },
          { title: "Control Total", desc: "Pots eliminar la memòria de Nova en qualsevol moment." },
          { title: "Sense Compartir", desc: "Les dades de Nova mai es comparteixen amb tercers." }
        ]
      },
      dataUsage: {
        title: "Ús de les Dades",
        neverSell: "Mai venem les teves dades a tercers",
        items: [
          "Proporcionar i personalitzar la teva experiència a Moments",
          "Permetre que Nova t'ofereixi assistència personalitzada i contextual",
          "Connectar amb altres usuaris segons els teus interessos",
          "Enviar notificacions i comunicacions rellevants",
          "Millorar els nostres serveis i garantir la seguretat"
        ]
      },
      security: {
        title: "Emmagatzematge i Seguretat",
        subtitle: "Les teves dades s'emmagatzemen en servidors segurs gestionats per Firebase. Implementem:",
        items: [
          { title: "Encriptació End-to-End", desc: "Per a dades sensibles i converses amb Nova" },
          { title: "Encriptació en Repòs", desc: "Totes les dades emmagatzemades estan encriptades" },
          { title: "Accés Restringit", desc: "Només personal autoritzat amb necessitat legítima" },
          { title: "Auditories Regulars", desc: "Revisions de seguretat periòdiques" }
        ]
      },
      rights: {
        title: "Els Teus Drets",
        subtitle: "Tens dret a:",
        items: [
          "Accedir a totes les teves dades, incloent l'historial amb Nova",
          "Corregir informació incorrecta",
          "Eliminar el teu compte i totes les dades associades",
          "Exportar les teves dades en format estàndard (JSON/CSV)",
          "Reiniciar la memòria de Nova",
          "Controlar la visibilitat del teu contingut",
          "Desactivar notificacions i comunicacions"
        ]
      },
      contact: {
        title: "Contacte",
        subtitle: "Si tens preguntes sobre aquesta política o sobre com protegim la teva privacitat:",
        email: "support@momentsapp.app",
        assistant: "Pregunta-li a Nova",
        web: "momentsapp.app"
      },
      commitment: {
        title: "Compromís Final",
        subtitle: "A Moments, creiem que la privacitat és un dret fonamental. El nostre compromís:",
        items: [
          "El teu contingut, les teves regles",
          "Les teves dades mai es venen",
          "Transparència total",
          "Control absolut",
          "Nova respecta la teva privacitat"
        ],
        quote: "Cada moment és teu. La teva privacitat també."
      },
      footer: {
        copyright: "© 2025 Moments - Xarxa Social Centrada en Privacitat",
        website: "momentsapp.app"
      }
    }
  };

  const t = translations[language];

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 via-blue-50 to-indigo-50">
      <div className="max-w-4xl mx-auto px-6 py-12">
        {/* Language Selector */}
        <div className="flex justify-center mb-8">
          <div className="inline-flex items-center bg-white rounded-full shadow-sm border p-1">
            {[
              { code: 'es', name: 'Español', flag: '🇪🇸' },
              { code: 'en', name: 'English', flag: '🇺🇸' },
              { code: 'ca', name: 'Català', img: 'https://upload.wikimedia.org/wikipedia/commons/c/ce/Flag_of_Catalonia.svg' }
            ].map((lang) => (
              <button
                key={lang.code}
                onClick={() => setLanguage(lang.code)}
                className={`px-4 py-2 rounded-full text-sm font-medium transition-all ${
                  language === lang.code
                    ? 'bg-blue-600 text-white shadow-sm'
                    : 'text-gray-600 hover:text-gray-900 hover:bg-gray-50'
                }`}
              >
                {lang.img ? (
                  <img src={lang.img} alt="Senyera (Flag of Catalonia)" className="inline-block h-4 w-auto mr-2 align-[-2px]" />
                ) : (
                  <span className="mr-2">{lang.flag}</span>
                )}
                {lang.name}
              </button>
            ))}
          </div>
        </div>

        {/* Header */}
        <div className="text-center mb-16">
          <div className="inline-flex items-center justify-center w-16 h-16 bg-gradient-to-r from-blue-600 to-indigo-600 rounded-2xl mb-6">
            <Shield className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
            {t.title}
          </h1>
          <p className="text-lg text-gray-600 max-w-2xl mx-auto">
            {t.subtitle}
          </p>
          <div className="inline-flex items-center mt-6 px-4 py-2 bg-white rounded-full shadow-sm border">
            <div className="w-2 h-2 bg-green-500 rounded-full mr-2"></div>
            <span className="text-sm text-gray-600">{t.lastUpdate}</span>
          </div>
        </div>

        {/* Main Content */}
        <div className="bg-white rounded-3xl shadow-xl overflow-hidden">
          <div className="p-8 md:p-12">
            
            {/* Introduction */}
            <section className="mb-12">
              <div className="flex items-center mb-6">
                <div className="w-10 h-10 bg-blue-100 rounded-xl flex items-center justify-center mr-4">
                  <MessageCircle className="w-5 h-5 text-blue-600" />
                </div>
                <h2 className="text-2xl font-bold text-gray-900">{t.introduction.title}</h2>
              </div>
              <p className="text-gray-700 leading-relaxed text-lg">
                {t.introduction.content}
              </p>
            </section>

            {/* Data Collection */}
            <section className="mb-12">
              <div className="flex items-center mb-6">
                <div className="w-10 h-10 bg-purple-100 rounded-xl flex items-center justify-center mr-4">
                  <Eye className="w-5 h-5 text-purple-600" />
                </div>
                <h2 className="text-2xl font-bold text-gray-900">{t.dataCollection.title}</h2>
              </div>
              <p className="text-gray-700 mb-6">{t.dataCollection.subtitle}</p>
              <div className="grid md:grid-cols-2 gap-4">
                {t.dataCollection.items.map((item, index) => {
                  const icons = [Users, Settings, Eye, MessageCircle];
                  const IconComponent = icons[index];
                  return (
                    <div key={index} className="p-4 bg-gray-50 rounded-xl border border-gray-100">
                      <div className="flex items-start">
                        <IconComponent className="w-5 h-5 text-indigo-600 mt-1 mr-3 flex-shrink-0" />
                        <div>
                          <h3 className="font-semibold text-gray-900 mb-1">{item.title}</h3>
                          <p className="text-sm text-gray-600">{item.desc}</p>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </section>

            {/* Nova Section */}
            <section className="mb-12">
              <div className="bg-gradient-to-r from-indigo-500 to-purple-600 rounded-2xl p-8 text-white">
                <div className="flex items-center mb-6">
                  <div className="w-12 h-12 bg-white/20 rounded-xl flex items-center justify-center mr-4">
                    <MessageCircle className="w-6 h-6 text-white" />
                  </div>
                  <h2 className="text-2xl font-bold">{t.nova.title}</h2>
                </div>
                <p className="text-indigo-100 mb-6 text-lg">
                  {t.nova.subtitle}
                </p>
                <div className="grid md:grid-cols-2 gap-4">
                  {t.nova.items.map((item, index) => (
                    <div key={index} className="flex items-start">
                      <Check className="w-5 h-5 text-green-300 mt-1 mr-3 flex-shrink-0" />
                      <div>
                        <h3 className="font-semibold mb-1">{item.title}</h3>
                        <p className="text-sm text-indigo-100">{item.desc}</p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </section>

            {/* Data Usage */}
            <section className="mb-12">
              <div className="flex items-center mb-6">
                <div className="w-10 h-10 bg-green-100 rounded-xl flex items-center justify-center mr-4">
                  <Settings className="w-5 h-5 text-green-600" />
                </div>
                <h2 className="text-2xl font-bold text-gray-900">{t.dataUsage.title}</h2>
              </div>
              <div className="bg-green-50 border border-green-200 rounded-xl p-6 mb-6">
                <div className="flex items-center mb-3">
                  <Shield className="w-5 h-5 text-green-600 mr-2" />
                  <span className="font-semibold text-green-800">{t.dataUsage.neverSell}</span>
                </div>
              </div>
              <div className="space-y-3">
                {t.dataUsage.items.map((item, index) => (
                  <div key={index} className="flex items-start">
                    <Check className="w-5 h-5 text-green-600 mt-0.5 mr-3 flex-shrink-0" />
                    <span className="text-gray-700">{item}</span>
                  </div>
                ))}
              </div>
            </section>

            {/* Security */}
            <section className="mb-12">
              <div className="flex items-center mb-6">
                <div className="w-10 h-10 bg-red-100 rounded-xl flex items-center justify-center mr-4">
                  <Lock className="w-5 h-5 text-red-600" />
                </div>
                <h2 className="text-2xl font-bold text-gray-900">{t.security.title}</h2>
              </div>
              <p className="text-gray-700 mb-6">{t.security.subtitle}</p>
              <div className="grid md:grid-cols-2 gap-4">
                {t.security.items.map((item, index) => {
                  const colors = ["blue", "purple", "green", "orange"];
                  const color = colors[index];
                  return (
                    <div key={index} className={`p-4 bg-${color}-50 border border-${color}-200 rounded-xl`}>
                      <h3 className={`font-semibold text-${color}-800 mb-2`}>{item.title}</h3>
                      <p className={`text-sm text-${color}-700`}>{item.desc}</p>
                    </div>
                  );
                })}
              </div>
            </section>

            {/* Your Rights */}
            <section className="mb-12">
              <div className="flex items-center mb-6">
                <div className="w-10 h-10 bg-indigo-100 rounded-xl flex items-center justify-center mr-4">
                  <Users className="w-5 h-5 text-indigo-600" />
                </div>
                <h2 className="text-2xl font-bold text-gray-900">{t.rights.title}</h2>
              </div>
              <div className="bg-indigo-50 border border-indigo-200 rounded-xl p-6">
                <p className="text-indigo-800 mb-4 font-medium">{t.rights.subtitle}</p>
                <div className="grid md:grid-cols-2 gap-3">
                  {t.rights.items.map((right, index) => (
                    <div key={index} className="flex items-start">
                      <Check className="w-4 h-4 text-indigo-600 mt-1 mr-2 flex-shrink-0" />
                      <span className="text-sm text-indigo-700">{right}</span>
                    </div>
                  ))}
                </div>
              </div>
            </section>

            {/* Contact */}
            <section className="mb-12">
              <div className="bg-gradient-to-r from-gray-900 to-gray-800 rounded-2xl p-8 text-white">
                <div className="flex items-center mb-6">
                  <div className="w-12 h-12 bg-white/10 rounded-xl flex items-center justify-center mr-4">
                    <Mail className="w-6 h-6 text-white" />
                  </div>
                  <h2 className="text-2xl font-bold">{t.contact.title}</h2>
                </div>
                <p className="text-gray-300 mb-6">{t.contact.subtitle}</p>
                <div className="grid md:grid-cols-3 gap-4">
                  <div className="flex items-center p-4 bg-white/5 rounded-xl">
                    <Mail className="w-5 h-5 text-blue-400 mr-3" />
                    <div>
                      <p className="text-sm text-gray-400">Email</p>
                      <p className="font-medium">{t.contact.email}</p>
                    </div>
                  </div>
                  <div className="flex items-center p-4 bg-white/5 rounded-xl">
                    <MessageCircle className="w-5 h-5 text-purple-400 mr-3" />
                    <div>
                      <p className="text-sm text-gray-400">Asistente</p>
                      <p className="font-medium">{t.contact.assistant}</p>
                    </div>
                  </div>
                  <div className="flex items-center p-4 bg-white/5 rounded-xl">
                    <Globe className="w-5 h-5 text-green-400 mr-3" />
                    <div>
                      <p className="text-sm text-gray-400">Web</p>
                      <p className="font-medium">{t.contact.web}</p>
                    </div>
                  </div>
                </div>
              </div>
            </section>

            {/* Final Commitment */}
            <section className="text-center">
              <div className="bg-gradient-to-r from-green-500 to-emerald-600 rounded-2xl p-8 text-white">
                <h2 className="text-2xl font-bold mb-4">{t.commitment.title}</h2>
                <p className="text-green-100 mb-6 text-lg">
                  {t.commitment.subtitle}
                </p>
                <div className="grid md:grid-cols-3 gap-4 mb-6">
                  {t.commitment.items.map((commitment, index) => (
                    <div key={index} className="flex items-center justify-center">
                      <Check className="w-5 h-5 text-green-300 mr-2" />
                      <span className="text-sm font-medium">{commitment}</span>
                    </div>
                  ))}
                </div>
                <div className="text-2xl font-bold text-green-100">
                  "{t.commitment.quote}"
                </div>
              </div>
            </section>
          </div>
        </div>

        {/* Footer */}
        <div className="text-center mt-12 text-gray-500">
          <p className="mb-2">{t.footer.copyright}</p>
          <p className="text-sm">{t.footer.website}</p>
        </div>
      </div>
    </div>
  );
};

export default PrivacyPolicy;
