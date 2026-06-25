cmake_minimum_required(VERSION 3.10.2)
project(naggly_afis)

# OpenCV sera lié lors de la compilation NDK
# Pour l'instant, on compile le moteur AFIS sans OpenCV externe
# (les fonctions morphologiques sont implémentées manuellement)

add_library(naggly_afis SHARED naggly_afis.cpp)

# Lien vers les bibliothèques Android de base
find_library(log-lib log)
target_link_libraries(naggly_afis ${log-lib})
