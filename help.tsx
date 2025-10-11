import React, { useState } from 'react';
import { HelpCircle, MessageCircle, Mail, Globe, Check, Search, BookOpen, Users, Shield, Settings } from 'lucide-react';

const HelpCenter = () => {
  const [language, setLanguage] = useState<'es' | 'en' | 'ca'>('es');

  const translations = {
    es: {
      title: "Centro de Ayuda",
      subtitle: "Encuentra respuestas a las preguntas más frecuentes y obtén soporte personalizado.",
      supportAvailable: "Soporte disponible 24/7",
      quickSearch: "Búsqueda Rápida",
      searchPlaceholder: "Busca en el centro de ayuda...",
      faq: "Preguntas Frecuentes",
      faqs: [
        {
          question: "¿Cómo cambio mi contraseña?",
          answer: "Ve a Configuración > Cuenta > Contraseña y sigue los pasos indicados para crear una nueva contraseña segura."
        },
        {
          question: "¿Cómo reporto contenido inapropiado?",
          answer: "Toca los tres puntos en cualquier momento y selecciona 'Reportar'. Nuestro equipo revisará el contenido en 24 horas."
        },
        {
          question: "¿Cómo activo la autenticación en dos pasos?",
          answer: "Configuración > Cuenta > Autenticación en dos pasos. Te recomendamos activarla para mayor seguridad."
        },
        {
          question: "¿Cómo elimino mi cuenta?",
          answer: "Configuración > Cuenta > Eliminar cuenta. Ten en cuenta que esta acción es irreversible."
        },
        {
          question: "¿Cómo exporto mis datos?",
          answer: "Configuración > Privacidad > Descargar datos. Recibirás un email con tus datos en formato JSON/CSV."
        }
      ],
      quickActions: "Acciones Rápidas",
      quickActionsSubtitle: "Accede directamente a las funciones más utilizadas:",
      actions: [
        { title: "Configuración de Cuenta", desc: "Gestiona tu perfil, contraseña y preferencias." },
        { title: "Notificaciones", desc: "Personaliza qué notificaciones recibes y cuándo." },
        { title: "Privacidad", desc: "Controla quién puede ver tu contenido y datos." },
        { title: "Seguridad", desc: "Activa autenticación en dos pasos y revisa sesiones." }
      ],
      contact: "Contacto Directo",
      contactSubtitle: "¿No encontraste lo que buscabas? Estamos aquí para ayudarte:",
      email: "Email",
      assistant: "Asistente",
      web: "Web",
      additionalResources: "Recursos Adicionales",
      additionalResourcesSubtitle: "Explora más información sobre Moments:",
      resources: [
        "Términos de Uso",
        "Política de Privacidad", 
        "Reportar Problema",
        "Guía de Usuario",
        "Novedades y Actualizaciones"
      ],
      quote: "Tu éxito es nuestro éxito",
      copyright: "© 2025 Moments - Red Social Centrada en Privacidad",
      website: "momentsapp.app"
    },
    en: {
      title: "Help Center",
      subtitle: "Find answers to frequently asked questions and get personalized support.",
      supportAvailable: "24/7 Support Available",
      quickSearch: "Quick Search",
      searchPlaceholder: "Search the help center...",
      faq: "Frequently Asked Questions",
      faqs: [
        {
          question: "How do I change my password?",
          answer: "Go to Settings > Account > Password and follow the steps to create a new secure password."
        },
        {
          question: "How do I report inappropriate content?",
          answer: "Tap the three dots on any moment and select 'Report'. Our team will review the content within 24 hours."
        },
        {
          question: "How do I enable two-factor authentication?",
          answer: "Settings > Account > Two-factor authentication. We recommend enabling it for better security."
        },
        {
          question: "How do I delete my account?",
          answer: "Settings > Account > Delete account. Note that this action is irreversible."
        },
        {
          question: "How do I export my data?",
          answer: "Settings > Privacy > Download data. You'll receive an email with your data in JSON/CSV format."
        }
      ],
      quickActions: "Quick Actions",
      quickActionsSubtitle: "Access the most used features directly:",
      actions: [
        { title: "Account Settings", desc: "Manage your profile, password and preferences." },
        { title: "Notifications", desc: "Customize which notifications you receive and when." },
        { title: "Privacy", desc: "Control who can see your content and data." },
        { title: "Security", desc: "Enable two-factor authentication and review sessions." }
      ],
      contact: "Direct Contact",
      contactSubtitle: "Didn't find what you were looking for? We're here to help:",
      email: "Email",
      assistant: "Assistant",
      web: "Web",
      additionalResources: "Additional Resources",
      additionalResourcesSubtitle: "Explore more information about Moments:",
      resources: [
        "Terms of Use",
        "Privacy Policy",
        "Report Problem",
        "User Guide",
        "News and Updates"
      ],
      quote: "Your success is our success",
      copyright: "© 2025 Moments - Privacy-Focused Social Network",
      website: "momentsapp.app"
    },
    ca: {
      title: "Centre d'Ajuda",
      subtitle: "Troba respostes a les preguntes més freqüents i obtén suport personalitzat.",
      supportAvailable: "Suport disponible 24/7",
      quickSearch: "Cerca Ràpida",
      searchPlaceholder: "Cerca al centre d'ajuda...",
      faq: "Preguntes Freqüents",
      faqs: [
        {
          question: "Com canvio la meva contrasenya?",
          answer: "Ves a Configuració > Compte > Contrasenya i segueix els passos indicats per crear una nova contrasenya segura."
        },
        {
          question: "Com reporto contingut inadequat?",
          answer: "Toca els tres punts en qualsevol moment i selecciona 'Reportar'. El nostre equip revisarà el contingut en 24 hores."
        },
        {
          question: "Com activo l'autenticació en dos passos?",
          answer: "Configuració > Compte > Autenticació en dos passos. Et recomanem activar-la per major seguretat."
        },
        {
          question: "Com elimino el meu compte?",
          answer: "Configuració > Compte > Eliminar compte. Tingues en compte que aquesta acció és irreversible."
        },
        {
          question: "Com exporto les meves dades?",
          answer: "Configuració > Privacitat > Descarregar dades. Rebràs un email amb les teves dades en format JSON/CSV."
        }
      ],
      quickActions: "Accions Ràpides",
      quickActionsSubtitle: "Accedeix directament a les funcions més utilitzades:",
      actions: [
        { title: "Configuració de Compte", desc: "Gestiona el teu perfil, contrasenya i preferències." },
        { title: "Notificacions", desc: "Personalitza quines notificacions reps i quan." },
        { title: "Privacitat", desc: "Controla qui pot veure el teu contingut i dades." },
        { title: "Seguretat", desc: "Activa autenticació en dos passos i revisa sessions." }
      ],
      contact: "Contacte Directe",
      contactSubtitle: "No has trobat el que buscaves? Estem aquí per ajudar-te:",
      email: "Email",
      assistant: "Assistenta",
      web: "Web",
      additionalResources: "Recursos Adicionals",
      additionalResourcesSubtitle: "Explora més informació sobre Moments:",
      resources: [
        "Termes d'Ús",
        "Política de Privacitat",
        "Reportar Problema",
        "Guia d'Usuari",
        "Novetats i Actualitzacions"
      ],
      quote: "El teu èxit és el nostre èxit",
      copyright: "© 2025 Moments - Xarxa Social Centrada en Privacitat",
      website: "momentsapp.app"
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
            <HelpCircle className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
            {t.title}
          </h1>
          <p className="text-lg text-gray-600 max-w-2xl mx-auto">
            {t.subtitle}
          </p>
          <div className="inline-flex items-center mt-6 px-4 py-2 bg-white rounded-full shadow-sm border">
            <div className="w-2 h-2 bg-green-500 rounded-full mr-2"></div>
            <span className="text-sm text-gray-600">{t.supportAvailable}</span>
          </div>
        </div>

        {/* Main Content */}
        <div className="bg-white rounded-3xl shadow-xl overflow-hidden">
          <div className="p-8 md:p-12">
            
            {/* Search Section */}
            <section className="mb-12">
              <div className="flex items-center mb-6">
                <div className="w-10 h-10 bg-blue-100 rounded-xl flex items-center justify-center mr-4">
                  <Search className="w-5 h-5 text-blue-600" />
                </div>
                <h2 className="text-2xl font-bold text-gray-900">{t.quickSearch}</h2>
              </div>
              <div className="relative">
                <input
                  type="text"
                  placeholder={t.searchPlaceholder}
                  className="w-full px-4 py-3 pl-12 border border-gray-200 rounded-xl focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
                <Search className="w-5 h-5 text-gray-400 absolute left-4 top-1/2 transform -translate-y-1/2" />
              </div>
            </section>

            {/* FAQ Section */}
            <section className="mb-12">
              <div className="flex items-center mb-6">
                <div className="w-10 h-10 bg-purple-100 rounded-xl flex items-center justify-center mr-4">
                  <BookOpen className="w-5 h-5 text-purple-600" />
                </div>
                <h2 className="text-2xl font-bold text-gray-900">{t.faq}</h2>
              </div>
              <div className="space-y-4">
                {t.faqs.map((faq, index) => (
                  <div key={index} className="p-6 bg-gray-50 rounded-xl border border-gray-100">
                    <h3 className="font-semibold text-gray-900 mb-2">{faq.question}</h3>
                    <p className="text-gray-600">{faq.answer}</p>
                  </div>
                ))}
              </div>
            </section>

            {/* Quick Actions */}
            <section className="mb-12">
              <div className="bg-gradient-to-r from-indigo-500 to-purple-600 rounded-2xl p-8 text-white">
                <div className="flex items-center mb-6">
                  <div className="w-12 h-12 bg-white/20 rounded-xl flex items-center justify-center mr-4">
                    <Settings className="w-6 h-6 text-white" />
                  </div>
                  <h2 className="text-2xl font-bold">{t.quickActions}</h2>
                </div>
                <p className="text-indigo-100 mb-6 text-lg">
                  {t.quickActionsSubtitle}
                </p>
                <div className="grid md:grid-cols-2 gap-4">
                  {t.actions.map((action, index) => (
                    <div key={index} className="flex items-start">
                      <Check className="w-5 h-5 text-green-300 mt-1 mr-3 flex-shrink-0" />
                      <div>
                        <h3 className="font-semibold mb-1">{action.title}</h3>
                        <p className="text-sm text-indigo-100">{action.desc}</p>
                      </div>
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
                    <MessageCircle className="w-6 h-6 text-white" />
                  </div>
                  <h2 className="text-2xl font-bold">{t.contact}</h2>
                </div>
                <p className="text-gray-300 mb-6">{t.contactSubtitle}</p>
                <div className="grid md:grid-cols-3 gap-4">
                  <div className="flex items-center p-4 bg-white/5 rounded-xl">
                    <Mail className="w-5 h-5 text-blue-400 mr-3" />
                    <div>
                      <p className="text-sm text-gray-400">{t.email}</p>
                      <p className="font-medium">support@momentsapp.app</p>
                    </div>
                  </div>
                  <div className="flex items-center p-4 bg-white/5 rounded-xl">
                    <MessageCircle className="w-5 h-5 text-purple-400 mr-3" />
                    <div>
                      <p className="text-sm text-gray-400">{t.assistant}</p>
                      <p className="font-medium">Pregúntale a Nova</p>
                    </div>
                  </div>
                  <div className="flex items-center p-4 bg-white/5 rounded-xl">
                    <Globe className="w-5 h-5 text-green-400 mr-3" />
                    <div>
                      <p className="text-sm text-gray-400">{t.web}</p>
                      <p className="font-medium">momentsapp.app</p>
                    </div>
                  </div>
                </div>
              </div>
            </section>

            {/* Additional Resources */}
            <section className="text-center">
              <div className="bg-gradient-to-r from-green-500 to-emerald-600 rounded-2xl p-8 text-white">
                <h2 className="text-2xl font-bold mb-4">{t.additionalResources}</h2>
                <p className="text-green-100 mb-6 text-lg">
                  {t.additionalResourcesSubtitle}
                </p>
                <div className="grid md:grid-cols-3 gap-4 mb-6">
                  {t.resources.map((resource, index) => (
                    <div key={index} className="flex items-center justify-center">
                      <Check className="w-5 h-5 text-green-300 mr-2" />
                      <span className="text-sm font-medium">{resource}</span>
                    </div>
                  ))}
                </div>
                <div className="text-2xl font-bold text-green-100">
                  "{t.quote}"
                </div>
              </div>
            </section>
          </div>
        </div>

        {/* Footer */}
        <div className="text-center mt-12 text-gray-500">
          <p className="mb-2">{t.copyright}</p>
          <p className="text-sm">{t.website}</p>
        </div>
      </div>
    </div>
  );
};

export default HelpCenter;
