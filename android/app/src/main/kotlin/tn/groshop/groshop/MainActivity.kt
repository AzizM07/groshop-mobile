package tn.groshop.groshop

import android.content.Context
import android.graphics.Color
import android.graphics.Outline
import android.graphics.drawable.GradientDrawable
import android.view.LayoutInflater
import android.view.View
import android.view.ViewOutlineProvider
import android.widget.ImageView
import android.widget.TextView
import com.google.android.gms.ads.nativead.MediaView
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin.NativeAdFactory
import kotlin.math.roundToInt

/** Activité principale + carte pub GROSHOP (factory « groshopNativeAd »). */
class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine, "groshopNativeAd", GroshopNativeAdFactory(this),
        )
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "groshopNativeAd")
        super.cleanUpFlutterEngine(flutterEngine)
    }
}

/**
 * Remplit la carte pub (res/layout/groshop_native_ad.xml).
 * Zones cliquables = éléments enregistrés (image, titre, annonceur, logo,
 * bouton) — jamais le fond. Hauteur stable : les éléments absents du bas
 * sont rendus INVISIBLES (pas GONE) pour que l'image reste carrée.
 */
private class GroshopNativeAdFactory(private val context: Context) : NativeAdFactory {

    override fun createNativeAd(
        nativeAd: NativeAd,
        customOptions: MutableMap<String, Any>?,
    ): NativeAdView {
        val adView = LayoutInflater.from(context)
            .inflate(R.layout.groshop_native_ad, null) as NativeAdView
        val d = context.resources.displayMetrics.density

        // Image : coins arrondis comme les photos produit
        adView.findViewById<View>(R.id.ad_media_frame).roundCorners(10f * d)
        adView.findViewById<MediaView>(R.id.ad_media).let { media ->
            media.setImageScaleType(ImageView.ScaleType.CENTER_CROP)
            nativeAd.mediaContent?.let { media.mediaContent = it }
            adView.mediaView = media
        }

        // En-tête : logo (rond) + « Sponsorisé » + « · Annonceur »
        adView.findViewById<ImageView>(R.id.ad_icon).let { iv ->
            val drawable = nativeAd.icon?.drawable
            if (drawable != null) {
                iv.setImageDrawable(drawable)
                iv.roundOval()
                iv.visibility = View.VISIBLE
                adView.iconView = iv
            } else {
                iv.visibility = View.GONE
            }
        }
        adView.findViewById<TextView>(R.id.ad_advertiser).let { tv ->
            val name = nativeAd.advertiser ?: nativeAd.store
            if (name.isNullOrBlank()) {
                tv.visibility = View.GONE
            } else {
                tv.text = " · $name"
                tv.visibility = View.VISIBLE
                adView.advertiserView = tv
            }
        }

        // Titre (obligatoire)
        adView.findViewById<TextView>(R.id.ad_headline).let { tv ->
            tv.text = nativeAd.headline
            adView.headlineView = tv
        }

        // Étoiles + prix
        val stars = adView.findViewById<TextView>(R.id.ad_stars)
        val price = adView.findViewById<TextView>(R.id.ad_price)
        nativeAd.starRating.let { r ->
            if (r != null) {
                stars.text = starsLabel(r)
                stars.visibility = View.VISIBLE
                adView.starRatingView = stars
            } else {
                stars.visibility = View.GONE
            }
        }
        nativeAd.price.let { p ->
            if (!p.isNullOrBlank()) {
                price.text = if (nativeAd.starRating != null) "· $p" else p
                price.visibility = View.VISIBLE
                adView.priceView = price
            } else {
                price.visibility = View.GONE
            }
        }
        adView.findViewById<View>(R.id.ad_rating_row).visibility =
            if (stars.visibility == View.VISIBLE || price.visibility == View.VISIBLE) View.VISIBLE
            else View.INVISIBLE

        // Bouton : contour orange arrondi, texte Google non modifié
        adView.findViewById<TextView>(R.id.ad_call_to_action).let { tv ->
            val cta = nativeAd.callToAction
            if (cta.isNullOrBlank()) {
                tv.visibility = View.INVISIBLE
            } else {
                tv.text = cta
                tv.background = GradientDrawable().apply {
                    setColor(Color.TRANSPARENT)
                    setStroke((1.5f * d).roundToInt(), Color.parseColor("#FF7A00"))
                    cornerRadius = 14f * d
                }
                tv.visibility = View.VISIBLE
                adView.callToActionView = tv
            }
        }

        adView.setNativeAd(nativeAd)
        return adView
    }

    private fun starsLabel(rating: Double): String {
        val full = rating.roundToInt().coerceIn(0, 5)
        return "★".repeat(full) + "☆".repeat(5 - full) + " " + String.format("%.1f", rating)
    }

    private fun View.roundCorners(radiusPx: Float) {
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setRoundRect(0, 0, view.width, view.height, radiusPx)
            }
        }
        clipToOutline = true
    }

    private fun View.roundOval() {
        outlineProvider = object : ViewOutlineProvider() {
            override fun getOutline(view: View, outline: Outline) {
                outline.setOval(0, 0, view.width, view.height)
            }
        }
        clipToOutline = true
    }
}