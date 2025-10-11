import React, { useState } from 'react';
import { FileText, Shield, Users, Check, AlertTriangle, Lock, Globe, Mail, MessageCircle } from 'lucide-react';

const TermsOfUse = () => {
  const [language, setLanguage] = useState<'es' | 'en' | 'ca'>('es');

  const translations = {
    es: {
      title: "Términos de Uso",
      subtitle: "Al usar Moments, aceptas estos términos y condiciones que rigen tu uso de la plataforma.",
      lastUpdate: "Última actualización: 12 de agosto de 2025",
      introduction: {
        title: "Introducción",
        content: "Bienvenido a Moments. Estos términos de uso establecen las reglas y regulaciones para el uso de nuestra plataforma de redes sociales. Al acceder y usar Moments, aceptas estar sujeto a estos términos."
      },
      acceptableUse: {
        title: "Uso Aceptable",
        allowed: {
          title: "Lo que SÍ está permitido",
          items: [
            "Compartir momentos personales y experiencias",
            "Conectar con otros usuarios de manera respetuosa",
            "Usar Nova para asistencia y soporte",
            "Reportar contenido inapropiado",
            "Participar en la comunidad de forma constructiva"
          ]
        },
        notAllowed: {
          title: "Lo que NO está permitido",
          items: [
            "Contenido ilegal o dañino",
            "Acoso, bullying o comportamiento tóxico",
            "Spam o contenido comercial no autorizado",
            "Violación de derechos de autor",
            "Suplantación de identidad"
          ]
        }
      },
      userResponsibilities: {
        title: "Responsabilidades del Usuario",
        subtitle: "Como usuario de Moments, tienes ciertas responsabilidades:",
        items: [
          { title: "Seguridad de la Cuenta", desc: "Mantener la seguridad de tu cuenta y contraseña." },
          { title: "Respeto Mutuo", desc: "Tratar a otros usuarios con respeto y dignidad." },
          { title: "Reportar Problemas", desc: "Reportar contenido inapropiado cuando lo veas." },
          { title: "Cumplir Leyes", desc: "Respetar todas las leyes y regulaciones aplicables." }
        ]
      },
      platformResponsibilities: {
        title: "Responsabilidades de Moments",
        items: [
          {
            title: "Servicio Seguro",
            desc: "Proporcionar una plataforma segura y confiable para todos los usuarios."
          },
          {
            title: "Protección de Privacidad",
            desc: "Proteger tu información personal y respetar tu privacidad."
          },
          {
            title: "Moderación Activa",
            desc: "Revisar y moderar contenido reportado de manera oportuna."
          },
          {
            title: "Soporte Técnico",
            desc: "Proporcionar soporte técnico y asistencia cuando sea necesario."
          }
        ]
      },
      contentGuidelines: {
        title: "Directrices de Contenido",
        subtitle: "Para mantener una comunidad saludable, todo el contenido debe:",
        items: [
          "Ser apropiado para todas las edades",
          "Respetar los derechos de otros",
          "No promover violencia o odio",
          "Ser original o tener permisos",
          "No contener información falsa",
          "Respetar la privacidad ajena"
        ]
      },
      consequences: {
        title: "Consecuencias del Incumplimiento",
        subtitle: "El incumplimiento de estos términos puede resultar en:",
        items: [
          { action: "Advertencia", desc: "Primera infracción menor" },
          { action: "Suspensión", desc: "Infracciones repetidas o graves" },
          { action: "Baneo", desc: "Violaciones graves o múltiples" }
        ]
      },
      contact: {
        title: "Contacto",
        subtitle: "Si tienes preguntas sobre estos términos:",
        email: "Email",
        assistant: "Asistente",
        web: "Web"
      },
      commitment: {
        title: "Compromiso con la Comunidad",
        subtitle: "En Moments, creemos en crear una comunidad segura y respetuosa:",
        items: [
          "Protección del usuario",
          "Transparencia total",
          "Moderación justa",
          "Soporte 24/7",
          "Mejora continua"
        ],
        quote: "Juntos construimos una mejor comunidad"
      },
      footer: {
        copyright: "© 2025 Moments - Red Social Centrada en Privacidad",
        website: "momentsapp.app"
      }
    },
    en: {
      title: "Terms of Use",
      subtitle: "By using Moments, you accept these terms and conditions that govern your use of the platform.",
      lastUpdate: "Last updated: August 12, 2025",
      introduction: {
        title: "Introduction",
        content: "Welcome to Moments. These terms of use establish the rules and regulations for using our social media platform. By accessing and using Moments, you agree to be bound by these terms."
      },
      acceptableUse: {
        title: "Acceptable Use",
        allowed: {
          title: "What IS allowed",
          items: [
            "Share personal moments and experiences",
            "Connect with other users respectfully",
            "Use Nova for assistance and support",
            "Report inappropriate content",
            "Participate constructively in the community"
          ]
        },
        notAllowed: {
          title: "What is NOT allowed",
          items: [
            "Illegal or harmful content",
            "Harassment, bullying or toxic behavior",
            "Spam or unauthorized commercial content",
            "Copyright infringement",
            "Identity impersonation"
          ]
        }
      },
      userResponsibilities: {
        title: "User Responsibilities",
        subtitle: "As a Moments user, you have certain responsibilities:",
        items: [
          { title: "Account Security", desc: "Maintain the security of your account and password." },
          { title: "Mutual Respect", desc: "Treat other users with respect and dignity." },
          { title: "Report Issues", desc: "Report inappropriate content when you see it." },
          { title: "Comply with Laws", desc: "Respect all applicable laws and regulations." }
        ]
      },
      platformResponsibilities: {
        title: "Moments Responsibilities",
        items: [
          {
            title: "Secure Service",
            desc: "Provide a secure and reliable platform for all users."
          },
          {
            title: "Privacy Protection",
            desc: "Protect your personal information and respect your privacy."
          },
          {
            title: "Active Moderation",
            desc: "Review and moderate reported content in a timely manner."
          },
          {
            title: "Technical Support",
            desc: "Provide technical support and assistance when needed."
          }
        ]
      },
      contentGuidelines: {
        title: "Content Guidelines",
        subtitle: "To maintain a healthy community, all content must:",
        items: [
          "Be appropriate for all ages",
          "Respect the rights of others",
          "Not promote violence or hatred",
          "Be original or have permissions",
          "Not contain false information",
          "Respect others' privacy"
        ]
      },
      consequences: {
        title: "Consequences of Non-Compliance",
        subtitle: "Non-compliance with these terms may result in:",
        items: [
          { action: "Warning", desc: "First minor offense" },
          { action: "Suspension", desc: "Repeated or serious offenses" },
          { action: "Ban", desc: "Serious or multiple violations" }
        ]
      },
      contact: {
        title: "Contact",
        subtitle: "If you have questions about these terms:",
        email: "Email",
        assistant: "Assistant",
        web: "Web"
      },
      commitment: {
        title: "Community Commitment",
        subtitle: "At Moments, we believe in creating a safe and respectful community:",
        items: [
          "User protection",
          "Total transparency",
          "Fair moderation",
          "24/7 support",
          "Continuous improvement"
        ],
        quote: "Together we build a better community"
      },
      footer: {
        copyright: "© 2025 Moments - Privacy-Focused Social Network",
        website: "momentsapp.app"
      }
    },
    ca: {
      title: "Termes d'Ús",
      subtitle: "En utilitzar Moments, acceptes aquests termes i condicions que regeixen el teu ús de la plataforma.",
      lastUpdate: "Última actualització: 12 d'agost de 2025",
      introduction: {
        title: "Introducció",
        content: "Benvingut a Moments. Aquests termes d'ús estableixen les regles i regulacions per utilitzar la nostra plataforma de xarxa social. En accedir i utilitzar Moments, acceptes estar subjecte a aquests termes."
      },
      acceptableUse: {
        title: "Ús Acceptable",
        allowed: {
          title: "El que SÍ està permès",
          items: [
            "Compartir moments personals i experiències",
            "Connectar amb altres usuaris de manera respectuosa",
            "Utilitzar Nova per assistència i suport",
            "Reportar contingut inadequat",
            "Participar en la comunitat de forma constructiva"
          ]
        },
        notAllowed: {
          title: "El que NO està permès",
          items: [
            "Contingut il·legal o danyós",
            "Assetjament, bullying o comportament tòxic",
            "Spam o contingut comercial no autoritzat",
            "Violació de drets d'autor",
            "Suplantació d'identitat"
          ]
        }
      },
      userResponsibilities: {
        title: "Responsabilitats de l'Usuari",
        subtitle: "Com a usuari de Moments, tens certes responsabilitats:",
        items: [
          { title: "Seguretat del Compte", desc: "Mantenir la seguretat del teu compte i contrasenya." },
          { title: "Respecte Mutu", desc: "Tractar altres usuaris amb respecte i dignitat." },
          { title: "Reportar Problemes", desc: "Reportar contingut inadequat quan ho vegis." },
          { title: "Complir Lleis", desc: "Respectar totes les lleis i regulacions aplicables." }
        ]
      },
      platformResponsibilities: {
        title: "Responsabilitats de Moments",
        items: [
          {
            title: "Servei Segur",
            desc: "Proporcionar una plataforma segura i confiable per a tots els usuaris."
          },
          {
            title: "Protecció de Privacitat",
            desc: "Protegir la teva informació personal i respectar la teva privacitat."
          },
          {
            title: "Moderació Activa",
            desc: "Revisar i moderar contingut reportat de manera oportuna."
          },
          {
            title: "Suport Tècnic",
            desc: "Proporcionar suport tècnic i assistència quan sigui necessari."
          }
        ]
      },
      contentGuidelines: {
        title: "Directrius de Contingut",
        subtitle: "Per mantenir una comunitat saludable, tot el contingut ha de:",
        items: [
          "Ser apropiat per a totes les edats",
          "Respectar els drets d'altres",
          "No promoure violència o odi",
          "Ser original o tenir permisos",
          "No contenir informació falsa",
          "Respectar la privacitat aliena"
        ]
      },
      consequences: {
        title: "Conseqüències del No Compliment",
        subtitle: "El no compliment d'aquests termes pot resultar en:",
        items: [
          { action: "Advertència", desc: "Primera infracció menor" },
          { action: "Suspensió", desc: "Infraccions repetides o greus" },
          { action: "Baneig", desc: "Violacions greus o múltiples" }
        ]
      },
      contact: {
        title: "Contacte",
        subtitle: "Si tens preguntes sobre aquests termes:",
        email: "Email",
        assistant: "Assistenta",
        web: "Web"
      },
      commitment: {
        title: "Compromís amb la Comunitat",
        subtitle: "A Moments, creiem en crear una comunitat segura i respectuosa:",
        items: [
          "Protecció de l'usuari",
          "Transparència total",
          "Moderació justa",
          "Suport 24/7",
          "Millora contínua"
        ],
        quote: "Junts construïm una millor comunitat"
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
                onClick={() => setLanguage(lang.code as 'es' | 'en' | 'ca')}
                className={`px-4 py-2 rounded-full text-sm font-medium transition-all ${
                  language === (lang.code as 'es' | 'en' | 'ca')
                    ? 'bg-blue-600 text-white shadow-sm'
                    : 'text-gray-600 hover:text-gray-900 hover:bg-gray-50'
                }`}
              >
                {('img' in lang && lang.img) ? (
                  <img src={(lang as any).img} alt="Senyera (Flag of Catalonia)" className="inline-block h-4 w-auto mr-2 align-[-2px]" />
                ) : (
                  <span className="mr-2">{(lang as any).flag}</span>
                )}
                {lang.name}
              </button>
            ))}
          </div>
        </div>

        {/* Header */}
        <div className="text-center mb-16">
          <div className="inline-flex items-center justify-center w-16 h-16 bg-gradient-to-r from-blue-600 to-indigo-600 rounded-2xl mb-6">
            <FileText className="w-8 h-8 text-white" />
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
                  <Globe className="w-5 h-5 text-blue-600" />
                </div>
                <h2 className="text-2xl font-bold text-gray-900">{t.introduction.title}</h2>
              </div>
              <p className="text-gray-700 leading-relaxed text-lg">
                {t.introduction.content}
              </p>
            </section>

            {/* Acceptable Use */}
            <section className="mb-12">
              <div className="flex items-center mb-6">
                <div className="w-10 h-10 bg-green-100 rounded-xl flex items-center justify-center mr-4">
                  <Check className="w-5 h-5 text-green-600" />
                </div>
                <h2 className="text-2xl font-bold text-gray-900">{t.acceptableUse.title}</h2>
              </div>
              <div className="grid md:grid-cols-2 gap-6">
                <div className="bg-green-50 border border-green-200 rounded-xl p-6">
                  <h3 className="font-semibold text-green-800 mb-4 flex items-center">
                    <Check className="w-5 h-5 mr-2" />
                    {t.acceptableUse.allowed.title}
                  </h3>
                  <ul className="space-y-2 text-sm text-green-700">
                    {t.acceptableUse.allowed.items.map((item, index) => (
                      <li key={index}>• {item}</li>
                    ))}
                  </ul>
                </div>
                <div className="bg-red-50 border border-red-200 rounded-xl p-6">
                  <h3 className="font-semibold text-red-800 mb-4 flex items-center">
                    <AlertTriangle className="w-5 h-5 mr-2" />
                    {t.acceptableUse.notAllowed.title}
                  </h3>
                  <ul className="space-y-2 text-sm text-red-700">
                    {t.acceptableUse.notAllowed.items.map((item, index) => (
                      <li key={index}>• {item}</li>
                    ))}
                  </ul>
                </div>
              </div>
            </section>

            {/* User Responsibilities */}
            <section className="mb-12">
              <div className="bg-gradient-to-r from-indigo-500 to-purple-600 rounded-2xl p-8 text-white">
                <div className="flex items-center mb-6">
                  <div className="w-12 h-12 bg-white/20 rounded-xl flex items-center justify-center mr-4">
                    <Users className="w-6 h-6 text-white" />
                  </div>
                  <h2 className="text-2xl font-bold">{t.userResponsibilities.title}</h2>
                </div>
                <p className="text-indigo-100 mb-6 text-lg">
                  {t.userResponsibilities.subtitle}
                </p>
                <div className="grid md:grid-cols-2 gap-4">
                  {t.userResponsibilities.items.map((responsibility, index) => (
                    <div key={index} className="flex items-start">
                      <Check className="w-5 h-5 text-green-300 mt-1 mr-3 flex-shrink-0" />
                      <div>
                        <h3 className="font-semibold mb-1">{responsibility.title}</h3>
                        <p className="text-sm text-indigo-100">{responsibility.desc}</p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </section>

            {/* Platform Responsibilities */}
            <section className="mb-12">
              <div className="flex items-center mb-6">
                <div className="w-10 h-10 bg-purple-100 rounded-xl flex items-center justify-center mr-4">
                  <Shield className="w-5 h-5 text-purple-600" />
                </div>
                <h2 className="text-2xl font-bold text-gray-900">{t.platformResponsibilities.title}</h2>
              </div>
              <div className="grid md:grid-cols-2 gap-4">
                {t.platformResponsibilities.items.map((item, index) => {
                  const icons = [Shield, Lock, Users, MessageCircle];
                  const colors = ["purple", "blue", "green", "indigo"];
                  const IconComponent = icons[index];
                  const color = colors[index];
                  return (
                    <div key={index} className={`p-6 bg-${color}-50 rounded-xl border border-${color}-100`}>
                      <div className="flex items-start">
                        <IconComponent className={`w-6 h-6 text-${color}-600 mt-1 mr-3 flex-shrink-0`} />
                        <div>
                          <h3 className="font-semibold text-gray-900 mb-2">{item.title}</h3>
                          <p className="text-sm text-gray-600">{item.desc}</p>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </section>

            {/* Content Guidelines */}
            <section className="mb-12">
              <div className="bg-gradient-to-r from-green-500 to-emerald-600 rounded-2xl p-8 text-white">
                <div className="flex items-center mb-6">
                  <div className="w-12 h-12 bg-white/20 rounded-xl flex items-center justify-center mr-4">
                    <FileText className="w-6 h-6 text-white" />
                  </div>
                  <h2 className="text-2xl font-bold">{t.contentGuidelines.title}</h2>
                </div>
                <p className="text-green-100 mb-6 text-lg">
                  {t.contentGuidelines.subtitle}
                </p>
                <div className="grid md:grid-cols-2 gap-4">
                  {t.contentGuidelines.items.map((guideline, index) => (
                    <div key={index} className="flex items-center">
                      <Check className="w-5 h-5 text-green-300 mr-3" />
                      <span className="text-sm font-medium">{guideline}</span>
                    </div>
                  ))}
                </div>
              </div>
            </section>

            {/* Consequences */}
            <section className="mb-12">
              <div className="bg-gradient-to-r from-orange-500 to-red-600 rounded-2xl p-8 text-white">
                <div className="flex items-center mb-6">
                  <div className="w-12 h-12 bg-white/20 rounded-xl flex items-center justify-center mr-4">
                    <AlertTriangle className="w-6 h-6 text-white" />
                  </div>
                  <h2 className="text-2xl font-bold">{t.consequences.title}</h2>
                </div>
                <p className="text-orange-100 mb-6 text-lg">
                  {t.consequences.subtitle}
                </p>
                <div className="grid md:grid-cols-3 gap-4">
                  {t.consequences.items.map((consequence, index) => (
                    <div key={index} className="text-center">
                      <div className="text-2xl font-bold mb-2">{consequence.action}</div>
                      <p className="text-sm text-orange-100">{consequence.desc}</p>
                    </div>
                  ))}
                </div>
              </div>
            </section>

            {/* Contact Section */}
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
                      <p className="text-sm text-gray-400">{t.contact.email}</p>
                      <p className="font-medium">support@momentsapp.app</p>
                    </div>
                  </div>
                  <div className="flex items-center p-4 bg-white/5 rounded-xl">
                    <MessageCircle className="w-5 h-5 text-purple-400 mr-3" />
                    <div>
                      <p className="text-sm text-gray-400">{t.contact.assistant}</p>
                      <p className="font-medium">Pregúntale a Nova</p>
                    </div>
                  </div>
                  <div className="flex items-center p-4 bg-white/5 rounded-xl">
                    <Globe className="w-5 h-5 text-green-400 mr-3" />
                    <div>
                      <p className="text-sm text-gray-400">{t.contact.web}</p>
                      <p className="font-medium">momentsapp.app</p>
                    </div>
                  </div>
                </div>
              </div>
            </section>

            {/* Final Note */}
            <section className="text-center">
              <div className="bg-gradient-to-r from-blue-500 to-indigo-600 rounded-2xl p-8 text-white">
                <h2 className="text-2xl font-bold mb-4">{t.commitment.title}</h2>
                <p className="text-blue-100 mb-6 text-lg">
                  {t.commitment.subtitle}
                </p>
                <div className="grid md:grid-cols-3 gap-4 mb-6">
                  {t.commitment.items.map((commitment, index) => (
                    <div key={index} className="flex items-center justify-center">
                      <Check className="w-5 h-5 text-blue-300 mr-2" />
                      <span className="text-sm font-medium">{commitment}</span>
                    </div>
                  ))}
                </div>
                <div className="text-2xl font-bold text-blue-100">
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

export default TermsOfUse;
