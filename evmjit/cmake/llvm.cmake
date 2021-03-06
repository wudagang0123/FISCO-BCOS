
# Configures LLVM dependency
#
# This function handles everything needed to setup LLVM project.
# By default it downloads and builds LLVM from source.
# In case LLVM_DIR variable is set it tries to use the pointed pre-built
# LLVM package. LLVM_DIR should point LLVM's shared cmake files to be used
# by find_package(... CONFIG) function.
#
# Creates a target representing all required LLVM libraries and include path.
function(configure_llvm_project TARGET_NAME)
    if (LLVM_DIR)
        find_package(LLVM REQUIRED CONFIG)
        llvm_map_components_to_libnames(LIBS mcjit ipo x86codegen)

        # To create a fake imported library later on we need to know the
        # location of some library
        list(GET LIBS 0 MAIN_LIB)
        get_property(CONFIGS TARGET ${MAIN_LIB} PROPERTY IMPORTED_CONFIGURATIONS)
        list(GET CONFIGS 0 CONFIG)  # Just get the first one. Usually there is only one.
        if (CONFIG)
            get_property(MAIN_LIB TARGET ${MAIN_LIB} PROPERTY IMPORTED_LOCATION_${CONFIG})
        else()
            set(CONFIG Unknown)
            get_property(MAIN_LIB TARGET ${MAIN_LIB} PROPERTY IMPORTED_LOCATION)
        endif()
        message(STATUS "LLVM ${LLVM_VERSION} (${CONFIG}; ${LLVM_ENABLE_ASSERTIONS}; ${LLVM_DIR})")
        if (NOT EXISTS ${MAIN_LIB})
            # Add some diagnostics to detect issues before building.
            message(FATAL_ERROR "LLVM library not found: ${MAIN_LIB}")
        endif()
    else()
        # List of required LLVM libs.
        # Generated with `llvm-config --libs mcjit ipo x86codegen`
        # Only used here locally to setup the "llvm" imported target
        set(LIBS
            LLVMMCJIT
            LLVMX86CodeGen LLVMX86Desc LLVMX86Info LLVMMCDisassembler LLVMX86AsmPrinter
            LLVMX86Utils LLVMSelectionDAG LLVMAsmPrinter LLVMCodeGen
            LLVMInstrumentation LLVMBitWriter LLVMipo LLVMVectorize LLVMScalarOpts
            LLVMProfileData LLVMIRReader LLVMAsmParser LLVMInstCombine
            LLVMTransformUtils LLVMExecutionEngine LLVMTarget LLVMAnalysis
            LLVMRuntimeDyld LLVMObject LLVMMCParser LLVMBitReader LLVMMC
            LLVMCore LLVMSupport
        )

        # System libs that LLVM depend on.
        # See `llvm-config --system-libs`
        if (APPLE)
            set(SYSTEM_LIBS pthread)
        elseif (UNIX)
            set(SYSTEM_LIBS pthread dl)
        endif()

        if (${CMAKE_GENERATOR} STREQUAL "Unix Makefiles")
            set(BUILD_COMMAND $(MAKE))
        else()
            set(BUILD_COMMAND cmake --build <BINARY_DIR> --config Release)
        endif()

        include(ExternalProject)
        ExternalProject_Add(llvm-project
            PREFIX llvm
            BINARY_DIR llvm  # Build directly to install dir to avoid copy.
            SOURCE_DIR llvm/src/llvm
            URL http://llvm.org/releases/3.8.0/llvm-3.8.0.src.tar.xz
            URL_HASH SHA256=555b028e9ee0f6445ff8f949ea10e9cd8be0d084840e21fbbe1d31d51fc06e46
            CMAKE_ARGS -DCMAKE_BUILD_TYPE=Release
                       -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
                       -DLLVM_ENABLE_TERMINFO=OFF  # Disable terminal color support
                       -DLLVM_ENABLE_ZLIB=OFF      # Disable compression support -- not needed at all
                       -DLLVM_TARGETS_TO_BUILD=X86
                       -DLLVM_INCLUDE_TOOLS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF
                       -DLLVM_INCLUDE_TESTS=OFF
            BUILD_COMMAND   ${BUILD_COMMAND}
            INSTALL_COMMAND cmake --build <BINARY_DIR> --config Release --target install
            EXCLUDE_FROM_ALL TRUE
        )

        ExternalProject_Get_Property(llvm-project INSTALL_DIR)
        set(LLVM_LIBRARY_DIRS ${INSTALL_DIR}/lib)
        set(LLVM_INCLUDE_DIRS ${INSTALL_DIR}/include)
        file(MAKE_DIRECTORY ${LLVM_INCLUDE_DIRS})  # Must exists.

        foreach(LIB ${LIBS})
            list(APPEND LIBFILES "${LLVM_LIBRARY_DIRS}/${CMAKE_STATIC_LIBRARY_PREFIX}${LIB}${CMAKE_STATIC_LIBRARY_SUFFIX}")
        endforeach()

        # Pick one of the libraries to be the main one. It does not matter which one
        # but the imported target requires the IMPORTED_LOCATION property.
        list(GET LIBFILES 0 MAIN_LIB)
        list(REMOVE_AT LIBFILES 0)
        set(LIBS ${LIBFILES} ${SYSTEM_LIBS})
    endif()

    if (CMAKE_CXX_COMPILER_ID MATCHES "Clang")
        # Clang needs this to build LLVM. Weird that the GCC does not.
        set(DEFINES __STDC_LIMIT_MACROS __STDC_CONSTANT_MACROS)
    endif()

    # Create the target representing
    add_library(${TARGET_NAME} STATIC IMPORTED)
    set_property(TARGET ${TARGET_NAME} PROPERTY INTERFACE_COMPILE_DEFINITIONS ${DEFINES})
    set_property(TARGET ${TARGET_NAME} PROPERTY INTERFACE_INCLUDE_DIRECTORIES ${LLVM_INCLUDE_DIRS})
    set_property(TARGET ${TARGET_NAME} PROPERTY IMPORTED_LOCATION ${MAIN_LIB})
    set_property(TARGET ${TARGET_NAME} PROPERTY INTERFACE_LINK_LIBRARIES ${LIBS})
    if (TARGET llvm-project)
        add_dependencies(${TARGET_NAME} llvm-project)
    endif()
endfunction()
