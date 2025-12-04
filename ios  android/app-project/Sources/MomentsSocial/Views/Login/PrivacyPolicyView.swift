import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Políticas de Privacidad")
                        .font(.custom("Poppins-Bold", size: 24))
                        .foregroundColor(.black)
                    
                    Text("Última actualización: 7 de agosto de 2024")
                        .font(.custom("Poppins-Regular", size: 14))
                        .foregroundColor(.gray)
                    
                    Text("1. Introducción")
                        .font(.custom("Poppins-Bold", size: 18))
                    Text("Bienvenido a Moments. Nos comprometemos a proteger tu privacidad y a garantizar que tus datos personales sean manejados de manera segura y responsable. Esta política describe cómo recopilamos, usamos y protegemos tu información, incluyendo tu interacción con Nova, tu asistente personal.")
                        .font(.custom("Poppins-Regular", size: 16))
                    
                    Text("2. Datos que Recopilamos")
                        .font(.custom("Poppins-Bold", size: 18))
                    Text("Recopilamos la siguiente información cuando te registras o usas Moments:\n- **Datos de Registro**: Nombre de usuario, correo electrónico y contraseña.\n- **Datos de Perfil**: Intereses, publicaciones, conexiones y preferencias.\n- **Datos de Uso**: Interacciones en la app, como visitas a perfiles y mensajes.\n- **Interacciones con Nova**: Conversaciones, preferencias personalizadas y datos contextuales que compartes con tu asistente IA.")
                        .font(.custom("Poppins-Regular", size: 16))
                    
                    Text("3. Nova - Tu Asistente Personal")
                        .font(.custom("Poppins-Bold", size: 18))
                    Text("Nova es tu asistente IA personal en Moments. Para brindarte una experiencia personalizada:\n- **Memoria Contextual**: Nova recuerda información que compartes (como tu nombre, cumpleaños, intereses) para personalizar sus respuestas.\n- **Privacidad de Nova**: Las conversaciones con Nova son privadas y encriptadas. Solo tú tienes acceso a tu historial con Nova.\n- **Control Total**: Puedes eliminar la memoria de Nova o resetear tu historial en cualquier momento desde Configuración.\n- **Sin Compartir**: Los datos de Nova nunca se comparten con terceros ni se usan para publicidad.")
                        .font(.custom("Poppins-Regular", size: 16))
                    
                    Text("4. Uso de los Datos")
                        .font(.custom("Poppins-Bold", size: 18))
                    Text("Usamos tus datos para:\n- Proporcionar y personalizar tu experiencia en Moments.\n- Permitir que Nova te ofrezca asistencia personalizada y contextual.\n- Conectar con otros usuarios según tus intereses.\n- Enviar notificaciones y comunicaciones relevantes.\n- Mejorar nuestros servicios y garantizar la seguridad.\n- **Nunca vendemos tus datos** a terceros.")
                        .font(.custom("Poppins-Regular", size: 16))
                    
                    Text("5. Almacenamiento y Seguridad")
                        .font(.custom("Poppins-Bold", size: 18))
                    Text("Tus datos se almacenan en servidores seguros gestionados por Firebase. Implementamos:\n- **Encriptación End-to-End**: Para datos sensibles y conversaciones con Nova.\n- **Encriptación en Reposo**: Todos los datos almacenados están encriptados.\n- **Acceso Restringido**: Solo personal autorizado con necesidad legítima.\n- **Auditorías Regulares**: Revisiones de seguridad periódicas.")
                        .font(.custom("Poppins-Regular", size: 16))
                    
                    Text("6. Tus Derechos")
                        .font(.custom("Poppins-Bold", size: 18))
                    Text("Tienes derecho a:\n- **Acceder** a todos tus datos, incluyendo el historial con Nova.\n- **Corregir** información incorrecta.\n- **Eliminar** tu cuenta y todos los datos asociados.\n- **Exportar** tus datos en formato estándar (JSON/CSV).\n- **Resetear** la memoria de Nova.\n- **Controlar** la visibilidad de tu contenido.\n- **Desactivar** notificaciones y comunicaciones.\n\nContacta con nosotros en soporte@moments.app para ejercer estos derechos.")
                        .font(.custom("Poppins-Regular", size: 16))
                    
                    Text("7. Control de Privacidad")
                        .font(.custom("Poppins-Bold", size: 18))
                    Text("Moments te da control total sobre tu privacidad:\n- **Audiencias Personalizadas**: Elige quién ve cada momento (Todos, Conexiones, Amigos Cercanos, Solo yo).\n- **Listas Personalizadas**: Crea grupos específicos para compartir contenido.\n- **Modo Incógnito**: Navega sin dejar rastro de actividad.\n- **Estado en Línea**: Controla quién puede ver cuándo estás activo.")
                        .font(.custom("Poppins-Regular", size: 16))
                    
                    Text("8. Publicidad y Monetización")
                        .font(.custom("Poppins-Bold", size: 18))
                    Text("Para mantener Moments gratuito:\n- Mostramos anuncios mínimos y no invasivos a través de AdMob.\n- Los anuncios respetan tu configuración de privacidad.\n- **Moments Plus**: Opción sin anuncios disponible.\n- **Nunca vendemos tus datos personales** para publicidad.\n- Puedes optar por anuncios no personalizados en Configuración.")
                        .font(.custom("Poppins-Regular", size: 16))
                    
                    Text("9. Menores de Edad")
                        .font(.custom("Poppins-Bold", size: 18))
                    Text("Moments está diseñado para usuarios de 13 años o más. Si eres menor de 18 años, recomendamos supervisión parental. Nova está programada para proporcionar respuestas apropiadas para la edad.")
                        .font(.custom("Poppins-Regular", size: 16))
                    
                    Text("10. Cambios en la Política")
                        .font(.custom("Poppins-Bold", size: 18))
                    Text("Podemos actualizar esta política ocasionalmente. Te notificaremos sobre cambios significativos a través de:\n- Notificación en la app\n- Email registrado\n- Nova te informará de cambios importantes")
                        .font(.custom("Poppins-Regular", size: 16))
                    
                    Text("11. Contacto")
                        .font(.custom("Poppins-Bold", size: 18))
                    Text("Si tienes preguntas sobre esta política o sobre cómo protegemos tu privacidad:\n\n📧 Email: soporte@moments.app\n💬 Pregúntale a Nova sobre privacidad\n🌐 Web: moments.app/privacy")
                        .font(.custom("Poppins-Regular", size: 16))
                    
                    Text("12. Compromiso Final")
                        .font(.custom("Poppins-Bold", size: 18))
                    Text("En Moments, creemos que la privacidad es un derecho fundamental. Nuestro compromiso:\n\n✅ Tu contenido, tus reglas\n✅ Tus datos nunca se venden\n✅ Transparencia total\n✅ Control absoluto\n✅ Nova respeta tu privacidad\n\n**\"Cada momento es tuyo. Tu privacidad también.\"**")
                        .font(.custom("Poppins-Regular", size: 16))
                        .padding(.bottom, 30)
                }
                .padding()
            }
            // Android: Navigation bar title and items handled natively
            // .navigationBarTitle(...) and .navigationBarItems(...) - unavailable in macOS/Android
        }
    }
}

struct PrivacyPolicyView_Previews: PreviewProvider {
    static var previews: some View {
        PrivacyPolicyView()
    }
}
