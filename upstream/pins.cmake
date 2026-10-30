# Upstream releases and commits for the tvOS build, read from the game version
# files so that an update only changes upstream/*-baseline.json.
foreach(recomptv_pin_file shipwright-baseline.json spaghettikart-baseline.json starship-baseline.json
        ghostship-baseline.json)
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_LIST_DIR}/${recomptv_pin_file}")
endforeach()
file(READ "${CMAKE_CURRENT_LIST_DIR}/shipwright-baseline.json" recomptv_pins)
string(JSON RECOMPTV_SHIPWRIGHT_RELEASE GET "${recomptv_pins}" release)
string(JSON RECOMPTV_SHIPWRIGHT_REVISION GET "${recomptv_pins}" sources shipwright revision)
string(JSON RECOMPTV_LUS_REVISION GET "${recomptv_pins}" sources libultraship revision)
string(JSON RECOMPTV_TORCH_REVISION GET "${recomptv_pins}" sources torch revision)
file(READ "${CMAKE_CURRENT_LIST_DIR}/spaghettikart-baseline.json" recomptv_pins)
string(JSON RECOMPTV_SPAGHETTIKART_RELEASE GET "${recomptv_pins}" release)
file(READ "${CMAKE_CURRENT_LIST_DIR}/starship-baseline.json" recomptv_pins)
string(JSON RECOMPTV_STARSHIP_RELEASE GET "${recomptv_pins}" release)
file(READ "${CMAKE_CURRENT_LIST_DIR}/ghostship-baseline.json" recomptv_pins)
string(JSON RECOMPTV_GHOSTSHIP_RELEASE GET "${recomptv_pins}" release)
