# VoxTypeMac

[English](README.md) · [繁體中文](README.zh-Hant.md) · [简体中文](README.zh-Hans.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Русский](README.ru.md) · [Українська](README.uk.md)

VoxTypeMac es una aplicación de dictado para la barra de menús de macOS que
prioriza el uso local en Apple Silicon. Pulsa el atajo seleccionado, habla y
púlsalo de nuevo. La transcripción se envía al campo de texto que tenía el foco
al empezar la grabación.

## Requisitos

- macOS 27 o posterior en Apple Silicon
- Xcode 27
- shellcheck para ejecutar el verificador completo del código fuente
- Opcional: uv y las dependencias fijadas de Qwen3-ASR para el modelo local de
  mejora

La aplicación usa Apple Speech, AppKit, SwiftUI, AVFoundation y las API de
Accesibilidad. No tiene sistema de cuentas, analíticas, cliente de transcripción
en la nube ni depende de datos privados del usuario presentes en el árbol del
código fuente.

## Datos y privacidad

Las grabaciones, transcripciones, ajustes, modelos descargados, cachés y
archivos temporales se guardan en
~/Library/Application Support/VoxTypeMac/. El árbol de código fuente y los
archivos de distribución no incluyen esa carpeta. Apple puede descargar
recursos de voz en el almacenamiento que administra macOS. macOS también
administra TCC, los ítems de inicio de sesión y los registros del sistema.

VoxTypeMac solicita acceso al micrófono y a Reconocimiento de voz para dictar,
a Monitorización de entrada para el atajo global y a Accesibilidad para
verificar la inserción de texto. Si no se puede verificar la inserción, la
transcripción se conserva en el portapapeles.

## Compilar y verificar

~~~sh
./verify-source.sh
./build-app.sh
open "runtime/build/VoxTypeMac.app"
~~~

Los resultados de compilación se guardan en el directorio runtime/, que está
excluido del control de versiones. Las compilaciones de desarrollo usan firma
ad hoc, por lo que macOS puede volver a solicitar permisos después de una
recompilación. La identidad de firma estable para la distribución y la
notarización no forman parte de esta versión local del código fuente.

Para instalar la aplicación compilada en este Mac:

~~~sh
./install.sh
~~~

Esto reemplaza únicamente ~/Applications/VoxTypeMac.app. No modifica otras
instalaciones privadas ni sus datos.

## Mejora opcional con Qwen3-ASR

~~~sh
./script/install-qwen.sh
~~~

El script instala el entorno de Python fijado y el modelo dentro del directorio
Application Support de VoxTypeMac. Solo hace falta acceso a la red durante la
instalación; la inferencia se ejecuta localmente. Las versiones y licencias de
terceros figuran en THIRD_PARTY_NOTICES.md, config/qwen-asr.json y los
requisitos de Python bloqueados por hash.

## Estructura del código fuente

- Sources/VoxType/: aplicación, menú, grabación, reconocimiento, entrega y almacenamiento
- Tests/VoxTypeTests/: pruebas funcionales nativas y comprobaciones de límites de datos
- Resources/: metadatos de la aplicación, autorizaciones y recursos gráficos del producto
- config/: identidad del producto y dependencias fijadas del modelo opcional
- script/: herramientas para compilar, empaquetar, instalar el modelo y ejecutar localmente

El código fuente está disponible bajo la Licencia MIT. Los modelos y entornos de ejecución opcionales mantienen sus propias condiciones.
