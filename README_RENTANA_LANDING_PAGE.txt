RENTANA LANDING PAGE PATCH

This patch makes https://rentana.online/ open a public marketing page where landlords can understand Rentana and download the Android app.

FILES INCLUDED:
- src/main/resources/static/index.html
- src/main/resources/static/assets/landing.css
- src/main/resources/static/assets/landing.js
- src/main/resources/static/assets/rentana-social-card.svg
- src/main/resources/static/favicon.svg
- src/main/resources/static/manifest.webmanifest
- src/main/resources/static/robots.txt
- src/main/resources/static/sitemap.xml
- src/main/kotlin/com/rentmanagement/rentapi/controller/AppDownloadController.kt
- src/main/kotlin/com/rentmanagement/rentapi/config/SecurityConfig.kt
- src/main/kotlin/com/rentmanagement/rentapi/config/WebConfig.kt
- src/main/resources/application.yaml

HOW DOWNLOAD WORKS:
1) Best way: set Render environment variable RENTANA_APK_URL to a public APK link.
   Example: RENTANA_APK_URL=https://your-file-host.com/rentana.apk

2) Or copy the APK into backend before deployment:
   src/main/resources/static/download/rentana.apk

3) Or set Render environment variable RENTANA_APK_FILE to a server file path.

If no APK is available, /download/rentana.apk redirects back to the homepage download section with a warning.
