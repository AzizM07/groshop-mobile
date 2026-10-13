// lib/pages/auth/_shared/social_icons.dart
//
// Portage direct de SocialIcons.jsx (web) — mêmes tracés SVG exacts,
// rendus via flutter_svg pour rester pixel-perfect (pas de réinterprétation
// manuelle des paths).
//
// À ajouter dans pubspec.yaml :
//   dependencies:
//     flutter_svg: ^2.0.10

import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

const String _googleSvg = '''
<svg viewBox="0 0 48 48" xmlns="http://www.w3.org/2000/svg">
  <path fill="#FFC107" d="M43.611,20.083H42V20H24v8h11.303c-1.649,4.657-6.08,8-11.303,8c-6.627,0-12-5.373-12-12c0-6.627,5.373-12,12-12c3.059,0,5.842,1.154,7.961,3.039l5.657-5.657C34.046,6.053,29.268,4,24,4C12.955,4,4,12.955,4,24c0,11.045,8.955,20,20,20c11.045,0,20-8.955,20-20C44,22.659,43.862,21.35,43.611,20.083z"/>
  <path fill="#FF3D00" d="M6.306,14.691l6.571,4.819C14.655,15.108,18.961,12,24,12c3.059,0,5.842,1.154,7.961,3.039l5.657-5.657C34.046,6.053,29.268,4,24,4C16.318,4,9.656,8.337,6.306,14.691z"/>
  <path fill="#4CAF50" d="M24,44c5.166,0,9.86-1.977,13.409-5.192l-6.19-5.238C29.211,35.091,26.715,36,24,36c-5.202,0-9.619-3.317-11.283-7.946l-6.522,5.025C9.505,39.556,16.227,44,24,44z"/>
  <path fill="#1976D2" d="M43.611,20.083H42V20H24v8h11.303c-0.792,2.237-2.231,4.166-4.087,5.571c0.001-0.001,0.002-0.001,0.003-0.002l6.19,5.238C36.971,39.205,44,34,44,24C44,22.659,43.862,21.35,43.611,20.083z"/>
</svg>
''';

const String _facebookSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path fill="#1877F2" d="M24 12.073c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.99 4.388 10.954 10.125 11.854v-8.385H7.078v-3.47h3.047V9.43c0-3.007 1.792-4.669 4.533-4.669 1.312 0 2.686.235 2.686.235v2.953H15.83c-1.491 0-1.956.925-1.956 1.874v2.25h3.328l-.532 3.47h-2.796v8.385C19.612 23.027 24 18.062 24 12.073z"/>
</svg>
''';

const String _linkedInSvg = '''
<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
  <path fill="#0A66C2" d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433a2.062 2.062 0 01-2.063-2.065 2.063 2.063 0 112.063 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z"/>
</svg>
''';

class GoogleIcon extends StatelessWidget {
  final double size;
  const GoogleIcon({super.key, this.size = 22});
  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_googleSvg, width: size, height: size);
}

class FacebookIcon extends StatelessWidget {
  final double size;
  const FacebookIcon({super.key, this.size = 22});
  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_facebookSvg, width: size, height: size);
}

class LinkedInIcon extends StatelessWidget {
  final double size;
  const LinkedInIcon({super.key, this.size = 22});
  @override
  Widget build(BuildContext context) =>
      SvgPicture.string(_linkedInSvg, width: size, height: size);
}