find_path(PVD_INCLUDE_DIRS
    NAMES libpvd.h
)

find_library(PVD_LIBRARIES
    NAMES pvd
)

mark_as_advanced(
    PVD_INCLUDE_DIRS
    PVD_LIBRARIES
)
