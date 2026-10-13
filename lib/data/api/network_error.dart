import 'dart:io';

import 'package:dio/dio.dart';

/// true si l'erreur vient d'une absence de réseau / serveur injoignable
/// (et PAS d'une erreur métier 400/404/500).
bool isNetworkError(Object? error) {
  if (error is SocketException) return true;
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return true;
      case DioExceptionType.unknown:
        return error.error is SocketException ||
            error.error is HttpException ||
            error.error is HandshakeException;
      default:
        return false;
    }
  }
  return false;
}

/// Message propre pour les SnackBar (ajout panier, commande, etc.)
/// au lieu d'afficher le DioException brut.
String friendlyErrorMessage(Object error) {
  if (isNetworkError(error)) {
    return 'Pas de connexion Internet. Vérifiez votre connexion et réessayez.';
  }
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['detail'] is String) return data['detail'] as String;
  }
  return 'Une erreur est survenue. Réessayez.';
}