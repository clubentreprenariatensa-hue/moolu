#include <cstdint>
#include <cstring>
#include <cmath>
#include <vector>
#include <algorithm>

// ─────────────────────────────────────────────────────────────────────────────
// NAGGLY AFIS ENGINE — Version C++ autonome (sans OpenCV externe)
// Toutes les opérations d'image sont implémentées manuellement.
// ─────────────────────────────────────────────────────────────────────────────

struct Minutia {
    int x, y;
    int type; // 1 = terminaison, 3 = bifurcation
};

// ── 1. Conversion RGB → Niveaux de Gris ─────────────────────────────────────
static void toGrayscale(const uint8_t* rgb, uint8_t* gray, int w, int h) {
    for (int i = 0; i < w * h; i++) {
        int r = rgb[i * 3];
        int g = rgb[i * 3 + 1];
        int b = rgb[i * 3 + 2];
        gray[i] = static_cast<uint8_t>(0.299 * r + 0.587 * g + 0.114 * b);
    }
}

// ── 2. CLAHE simplifié (Amélioration locale du contraste) ───────────────────
static void applyCLAHE(uint8_t* gray, int w, int h) {
    // Calcul de l'histogramme global
    int hist[256] = {0};
    int total = w * h;
    for (int i = 0; i < total; i++) hist[gray[i]]++;

    // Histogramme cumulé normalisé
    int cum[256];
    cum[0] = hist[0];
    for (int i = 1; i < 256; i++) cum[i] = cum[i-1] + hist[i];
    for (int i = 0; i < total; i++) {
        gray[i] = static_cast<uint8_t>((cum[gray[i]] * 255) / total);
    }
}

// ── 3. Seuillage d'Otsu (Binarisation automatique) ──────────────────────────
static uint8_t otsuThreshold(const uint8_t* gray, int total) {
    int hist[256] = {0};
    for (int i = 0; i < total; i++) hist[gray[i]]++;

    double sum = 0;
    for (int i = 0; i < 256; i++) sum += i * hist[i];

    double sumB = 0;
    int wB = 0, wF = 0;
    double maxVar = 0;
    uint8_t bestThresh = 0;

    for (int t = 0; t < 256; t++) {
        wB += hist[t];
        if (wB == 0) continue;
        wF = total - wB;
        if (wF == 0) break;

        sumB += t * hist[t];
        double mB = sumB / wB;
        double mF = (sum - sumB) / wF;
        double var = (double)wB * wF * (mB - mF) * (mB - mF);
        if (var > maxVar) {
            maxVar = var;
            bestThresh = t;
        }
    }
    return bestThresh;
}

// ── 4. Black-Hat Morphologique (Extraction des crêtes) ──────────────────────
static void blackHat(const uint8_t* src, uint8_t* dst, int w, int h, int ksize) {
    int half = ksize / 2;
    std::vector<uint8_t> closed(w * h);

    // Dilatation
    std::vector<uint8_t> dilated(w * h);
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            uint8_t maxVal = 0;
            for (int ky = -half; ky <= half; ky++) {
                for (int kx = -half; kx <= half; kx++) {
                    int ny = y + ky, nx = x + kx;
                    if (ny >= 0 && ny < h && nx >= 0 && nx < w) {
                        uint8_t v = src[ny * w + nx];
                        if (v > maxVal) maxVal = v;
                    }
                }
            }
            dilated[y * w + x] = maxVal;
        }
    }

    // Érosion de la dilatation = Fermeture
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            uint8_t minVal = 255;
            for (int ky = -half; ky <= half; ky++) {
                for (int kx = -half; kx <= half; kx++) {
                    int ny = y + ky, nx = x + kx;
                    if (ny >= 0 && ny < h && nx >= 0 && nx < w) {
                        uint8_t v = dilated[ny * w + nx];
                        if (v < minVal) minVal = v;
                    }
                }
            }
            closed[y * w + x] = minVal;
        }
    }

    // Black-Hat = Fermeture - Original
    for (int i = 0; i < w * h; i++) {
        int diff = closed[i] - src[i];
        dst[i] = static_cast<uint8_t>(diff > 0 ? diff : 0);
    }
}

// ── 5. Squelettisation de Zhang-Suen ────────────────────────────────────────
static void zhangSuenIteration(uint8_t* img, int w, int h, int iter, bool& changed) {
    std::vector<uint8_t> marker(w * h, 0);

    for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
            if (img[y * w + x] == 0) continue;

            uint8_t p2 = img[(y-1)*w + x]     > 0 ? 1 : 0;
            uint8_t p3 = img[(y-1)*w + (x+1)] > 0 ? 1 : 0;
            uint8_t p4 = img[y*w + (x+1)]     > 0 ? 1 : 0;
            uint8_t p5 = img[(y+1)*w + (x+1)] > 0 ? 1 : 0;
            uint8_t p6 = img[(y+1)*w + x]     > 0 ? 1 : 0;
            uint8_t p7 = img[(y+1)*w + (x-1)] > 0 ? 1 : 0;
            uint8_t p8 = img[y*w + (x-1)]     > 0 ? 1 : 0;
            uint8_t p9 = img[(y-1)*w + (x-1)] > 0 ? 1 : 0;

            int A = (p2==0&&p3==1)+(p3==0&&p4==1)+(p4==0&&p5==1)+(p5==0&&p6==1)+
                    (p6==0&&p7==1)+(p7==0&&p8==1)+(p8==0&&p9==1)+(p9==0&&p2==1);
            int B = p2+p3+p4+p5+p6+p7+p8+p9;

            int m1 = iter==0 ? (p2*p4*p6) : (p2*p4*p8);
            int m2 = iter==0 ? (p4*p6*p8) : (p2*p6*p8);

            if (A==1 && B>=2 && B<=6 && m1==0 && m2==0) {
                marker[y*w+x] = 1;
            }
        }
    }

    for (int i = 0; i < w*h; i++) {
        if (marker[i]) { img[i] = 0; changed = true; }
    }
}

static void skeletonize(uint8_t* binary, int w, int h) {
    bool changed;
    do {
        changed = false;
        zhangSuenIteration(binary, w, h, 0, changed);
        zhangSuenIteration(binary, w, h, 1, changed);
    } while (changed);
}

// ── 6. Extraction des Minuties (Crossing Number) ───────────────────────────
static std::vector<Minutia> extractMinutiae(const uint8_t* skel, int w, int h) {
    std::vector<Minutia> minutiae;

    for (int y = 1; y < h - 1; y++) {
        for (int x = 1; x < w - 1; x++) {
            if (skel[y*w+x] == 0) continue;

            uint8_t p[8];
            p[0] = skel[(y-1)*w+(x-1)] > 0 ? 1 : 0;
            p[1] = skel[(y-1)*w+x]     > 0 ? 1 : 0;
            p[2] = skel[(y-1)*w+(x+1)] > 0 ? 1 : 0;
            p[3] = skel[y*w+(x+1)]     > 0 ? 1 : 0;
            p[4] = skel[(y+1)*w+(x+1)] > 0 ? 1 : 0;
            p[5] = skel[(y+1)*w+x]     > 0 ? 1 : 0;
            p[6] = skel[(y+1)*w+(x-1)] > 0 ? 1 : 0;
            p[7] = skel[y*w+(x-1)]     > 0 ? 1 : 0;

            int cn = 0;
            for (int i = 0; i < 8; i++) {
                if (p[i]==0 && p[(i+1)%8]==1) cn++;
            }

            if (cn == 1)  minutiae.push_back({x, y, 1}); // Terminaison
            if (cn >= 3)  minutiae.push_back({x, y, 3}); // Bifurcation
        }
    }
    return minutiae;
}

// ── 7. Point d'entrée FFI (appelé depuis Dart/Flutter) ──────────────────────
extern "C" __attribute__((visibility("default"))) __attribute__((used))
int process_naggly_afis(uint8_t* rgb, int w, int h, int* out_x, int* out_y) {
    int total = w * h;

    // 1. Grayscale
    std::vector<uint8_t> gray(total);
    toGrayscale(rgb, gray.data(), w, h);

    // 2. CLAHE
    applyCLAHE(gray.data(), w, h);

    // 3. Black-Hat (extraction des crêtes)
    std::vector<uint8_t> ridges(total);
    blackHat(gray.data(), ridges.data(), w, h, 11);

    // 4. Binarisation Otsu
    uint8_t thresh = otsuThreshold(ridges.data(), total);
    std::vector<uint8_t> binary(total);
    for (int i = 0; i < total; i++) {
        binary[i] = ridges[i] >= thresh ? 1 : 0;
    }

    // 5. Squelettisation
    skeletonize(binary.data(), w, h);

    // 6. Extraction des minuties
    auto minutiae = extractMinutiae(binary.data(), w, h);

    // 7. Copie des bifurcations dans le buffer de sortie
    int count = 0;
    for (const auto& m : minutiae) {
        if (m.type == 3 && count < 1000) { // Bifurcations uniquement
            out_x[count] = m.x;
            out_y[count] = m.y;
            count++;
        }
    }
    return count;
}
