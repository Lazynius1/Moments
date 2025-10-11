import React, { useState } from 'react';
import { AlertTriangle, MessageCircle, Mail, Globe, Check, Send, Bug, Shield, Clock, FileText } from 'lucide-react';

const ReportProblem = () => {
  const [language, setLanguage] = useState<'es' | 'en' | 'ca'>('es');

  const translations = {
    es: {
      title: "Reportar un Problema",
      subtitle: "Ayúdanos a mejorar Moments reportando cualquier problema que encuentres.",
      responseTime: "Respuesta en máximo 24 horas",
      problemTypes: "Tipos de Problemas",
      problems: [
        {
          title: "Problemas Técnicos",
          desc: "La app se cierra, notificaciones no funcionan, errores de conexión"
        },
        {
          title: "Problemas de Usuario",
          desc: "Comportamiento inapropiado, spam, problemas de privacidad"
        },
        {
          title: "Problemas de Contenido",
          desc: "Contenido inapropiado, reportes de moderación"
        },
        {
          title: "Sugerencias",
          desc: "Ideas para mejorar la app, nuevas funcionalidades"
        }
      ],
      reportProblem: "Reportar Problema",
      reportSubtitle: "Para reportar un problema, haz clic en el botón de abajo. Se abrirá nuestro formulario oficial donde podrás:",
      reportFeatures: [
        "Describir el problema detalladamente",
        "Seleccionar el tipo de problema",
        "Subir screenshots si es necesario",
        "Recibir confirmación por email"
      ],
      openForm: "Abrir Formulario de Reporte",
      formNote: "Se abrirá en una nueva pestaña",
      responseTimeTitle: "Tiempo de Respuesta",
      responseTimeSubtitle: "Nos comprometemos a responder a todos los reportes:",
      responseTimes: [
        { time: "24 horas", desc: "Para problemas técnicos críticos" },
        { time: "48 horas", desc: "Para reportes de contenido" },
        { time: "1 semana", desc: "Para sugerencias y mejoras" }
      ],
      contact: "Contacto Alternativo",
      contactSubtitle: "¿Prefieres contactarnos de otra forma?",
      email: "Email",
      assistant: "Asistente",
      web: "Web",
      thanks: "Gracias por tu Ayuda",
      thanksSubtitle: "Cada reporte nos ayuda a hacer Moments mejor para todos:",
      benefits: [
        "Mejoramos la app",
        "Corregimos errores",
        "Añadimos funcionalidades",
        "Protegemos la comunidad",
        "Escuchamos a los usuarios"
      ],
      quote: "Juntos hacemos Moments mejor",
      copyright: "© 2025 Moments - Red Social Centrada en Privacidad",
      website: "momentsapp.app"
    },
    en: {
      title: "Report a Problem",
      subtitle: "Help us improve Moments by reporting any issues you encounter.",
      responseTime: "Response within 24 hours",
      problemTypes: "Types of Problems",
      problems: [
        {
          title: "Technical Issues",
          desc: "App crashes, notifications not working, connection errors"
        },
        {
          title: "User Issues",
          desc: "Inappropriate behavior, spam, privacy problems"
        },
        {
          title: "Content Issues",
          desc: "Inappropriate content, moderation reports"
        },
        {
          title: "Suggestions",
          desc: "Ideas to improve the app, new features"
        }
      ],
      reportProblem: "Report Problem",
      reportSubtitle: "To report a problem, click the button below. Our official form will open where you can:",
      reportFeatures: [
        "Describe the problem in detail",
        "Select the type of problem",
        "Upload screenshots if necessary",
        "Receive email confirmation"
      ],
      openForm: "Open Report Form",
      formNote: "Will open in a new tab",
      responseTimeTitle: "Response Time",
      responseTimeSubtitle: "We commit to responding to all reports:",
      responseTimes: [
        { time: "24 hours", desc: "For critical technical issues" },
        { time: "48 hours", desc: "For content reports" },
        { time: "1 week", desc: "For suggestions and improvements" }
      ],
      contact: "Alternative Contact",
      contactSubtitle: "Prefer to contact us another way?",
      email: "Email",
      assistant: "Assistant",
      web: "Web",
      thanks: "Thanks for Your Help",
      thanksSubtitle: "Every report helps us make Moments better for everyone:",
      benefits: [
        "We improve the app",
        "We fix bugs",
        "We add features",
        "We protect the community",
        "We listen to users"
      ],
      quote: "Together we make Moments better",
      copyright: "© 2025 Moments - Privacy-Focused Social Network",
      website: "momentsapp.app"
    },
    ca: {
      title: "Reportar un Problema",
      subtitle: "Ajuda'ns a millorar Moments reportant qualsevol problema que trobis.",
      responseTime: "Resposta en màxim 24 hores",
      problemTypes: "Tipus de Problemes",
      problems: [
        {
          title: "Problemes Tècnics",
          desc: "L'app es tanca, les notificacions no funcionen, errors de connexió"
        },
        {
          title: "Problemes d'Usuari",
          desc: "Comportament inadequat, spam, problemes de privacitat"
        },
        {
          title: "Problemes de Contingut",
          desc: "Contingut inadequat, reportes de moderació"
        },
        {
          title: "Suggeriments",
          desc: "Idees per millorar l'app, noves funcionalitats"
        }
      ],
      reportProblem: "Reportar Problema",
      reportSubtitle: "Per reportar un problema, fes clic al botó de baix. S'obrirà el nostre formulari oficial on podràs:",
      reportFeatures: [
        "Descriure el problema detalladament",
        "Seleccionar el tipus de problema",
        "Pujar screenshots si cal",
        "Rebre confirmació per email"
      ],
      openForm: "Obrir Formulari de Reporte",
      formNote: "S'obrirà en una nova pestanya",
      responseTimeTitle: "Temps de Resposta",
      responseTimeSubtitle: "Ens comprometem a respondre a tots els reportes:",
      responseTimes: [
        { time: "24 hores", desc: "Per a problemes tècnics crítics" },
        { time: "48 hores", desc: "Per a reportes de contingut" },
        { time: "1 setmana", desc: "Per a suggeriments i millores" }
      ],
      contact: "Contacte Alternatiu",
      contactSubtitle: "Prefereixes contactar-nos d'una altra manera?",
      email: "Email",
      assistant: "Assistenta",
      web: "Web",
      thanks: "Gràcies per la Teva Ajuda",
      thanksSubtitle: "Cada reporte ens ajuda a fer Moments millor per a tothom:",
      benefits: [
        "Millorem l'app",
        "Corregim errors",
        "Afegim funcionalitats",
        "Protegim la comunitat",
        "Escoltem els usuaris"
      ],
      quote: "Junts fem Moments millor",
      copyright: "© 2025 Moments - Xarxa Social Centrada en Privacitat",
      website: "momentsapp.app"
    }
  };

  const t = translations[language];

  const handleSubmit = () => {
    // Abrir Google Form en nueva pestaña
    window.open('https://forms.gle/2VFZ988VGwYCRQYW7', '_blank');
  };

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
                    ? 'bg-orange-600 text-white shadow-sm'
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
          <div className="inline-flex items-center justify-center w-16 h-16 bg-gradient-to-r from-orange-600 to-red-600 rounded-2xl mb-6">
            <AlertTriangle className="w-8 h-8 text-white" />
          </div>
          <h1 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
            {t.title}
          </h1>
          <p className="text-lg text-gray-600 max-w-2xl mx-auto">
            {t.subtitle}
          </p>
          <div className="inline-flex items-center mt-6 px-4 py-2 bg-white rounded-full shadow-sm border">
            <div className="w-2 h-2 bg-green-500 rounded-full mr-2"></div>
            <span className="text-sm text-gray-600">{t.responseTime}</span>
          </div>
        </div>

        {/* Main Content */}
        <div className="bg-white rounded-3xl shadow-xl overflow-hidden">
          <div className="p-8 md:p-12">
            
            {/* Problem Types */}
            <section className="mb-12">
              <div className="flex items-center mb-6">
                <div className="w-10 h-10 bg-orange-100 rounded-xl flex items-center justify-center mr-4">
                  <Bug className="w-5 h-5 text-orange-600" />
                </div>
                <h2 className="text-2xl font-bold text-gray-900">{t.problemTypes}</h2>
              </div>
              <div className="grid md:grid-cols-2 gap-4">
                {t.problems.map((problem, index) => {
                  const icons = [Bug, Shield, FileText, MessageCircle];
                  const colors = ["orange", "red", "purple", "blue"];
                  const IconComponent = icons[index];
                  const color = colors[index];
                  return (
                    <div key={index} className={`p-6 bg-${color}-50 rounded-xl border border-${color}-100`}>
                      <div className="flex items-start">
                        <IconComponent className={`w-6 h-6 text-${color}-600 mt-1 mr-3 flex-shrink-0`} />
                        <div>
                          <h3 className="font-semibold text-gray-900 mb-2">{problem.title}</h3>
                          <p className="text-sm text-gray-600">{problem.desc}</p>
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </section>

            {/* Google Form Integration */}
            <section className="mb-12">
              <div className="bg-gradient-to-r from-indigo-500 to-purple-600 rounded-2xl p-8 text-white">
                <div className="flex items-center mb-6">
                  <div className="w-12 h-12 bg-white/20 rounded-xl flex items-center justify-center mr-4">
                    <FileText className="w-6 h-6 text-white" />
                  </div>
                  <h2 className="text-2xl font-bold">{t.reportProblem}</h2>
                </div>
                <p className="text-indigo-100 mb-6 text-lg">
                  {t.reportSubtitle}
                </p>
                <div className="grid md:grid-cols-2 gap-4 mb-8">
                  {t.reportFeatures.map((feature, index) => (
                    <div key={index} className="flex items-start">
                      <Check className="w-5 h-5 text-green-300 mt-1 mr-3 flex-shrink-0" />
                      <span className="text-sm text-indigo-100">{feature}</span>
                    </div>
                  ))}
                </div>
                <button
                  onClick={handleSubmit}
                  className="w-full bg-white text-indigo-600 py-4 px-8 rounded-xl font-semibold hover:bg-gray-50 transition-colors flex items-center justify-center text-lg"
                >
                  <Send className="w-6 h-6 mr-3" />
                  {t.openForm}
                </button>
                <p className="text-center text-indigo-200 text-sm mt-4">
                  {t.formNote}
                </p>
              </div>
            </section>

            {/* Response Time */}
            <section className="mb-12">
              <div className="bg-gradient-to-r from-green-500 to-emerald-600 rounded-2xl p-8 text-white">
                <div className="flex items-center mb-6">
                  <div className="w-12 h-12 bg-white/20 rounded-xl flex items-center justify-center mr-4">
                    <Clock className="w-6 h-6 text-white" />
                  </div>
                  <h2 className="text-2xl font-bold">{t.responseTimeTitle}</h2>
                </div>
                <p className="text-green-100 mb-6 text-lg">
                  {t.responseTimeSubtitle}
                </p>
                <div className="grid md:grid-cols-3 gap-4">
                  {t.responseTimes.map((item, index) => (
                    <div key={index} className="text-center">
                      <div className="text-3xl font-bold mb-2">{item.time}</div>
                      <p className="text-sm text-green-100">{item.desc}</p>
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

            {/* Final Note */}
            <section className="text-center">
              <div className="bg-gradient-to-r from-blue-500 to-indigo-600 rounded-2xl p-8 text-white">
                <h2 className="text-2xl font-bold mb-4">{t.thanks}</h2>
                <p className="text-blue-100 mb-6 text-lg">
                  {t.thanksSubtitle}
                </p>
                <div className="grid md:grid-cols-3 gap-4 mb-6">
                  {t.benefits.map((benefit, index) => (
                    <div key={index} className="flex items-center justify-center">
                      <Check className="w-5 h-5 text-blue-300 mr-2" />
                      <span className="text-sm font-medium">{benefit}</span>
                    </div>
                  ))}
                </div>
                <div className="text-2xl font-bold text-blue-100">
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

export default ReportProblem;
