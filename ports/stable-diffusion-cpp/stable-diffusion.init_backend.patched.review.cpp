// Review helper file: final init_backend form after local overlay patches.
// Source base: qvac-ext-stable-diffusion.cpp @ 5792c668798083f9f6d57dac66fbc62ddfdac405
// Applied patch: sd-generic-backend-init.patch

void init_backend(enum sd_backend_preference_t preferred_backend) {
    const char* pref_name = "auto";
    if (preferred_backend == SD_BACKEND_PREF_CPU) {
        pref_name = "cpu";
    } else if (preferred_backend == SD_BACKEND_PREF_GPU) {
        pref_name = "gpu";
    } else if (preferred_backend == SD_BACKEND_PREF_OPENCL) {
        pref_name = "opencl";
    }
    LOG_INFO("Backend preference requested: %s", pref_name);

    if (getenv("SD_CPU_ONLY")) {
        LOG_INFO("SD_CPU_ONLY set - using CPU backend");
        backend = ggml_backend_init_by_type(GGML_BACKEND_DEVICE_TYPE_CPU, NULL);
        if (!backend) {
            LOG_ERROR("SD_CPU_ONLY set but CPU backend failed to initialize");
        }
        return;
    }

    if (preferred_backend == SD_BACKEND_PREF_CPU) {
        backend = ggml_backend_init_by_type(GGML_BACKEND_DEVICE_TYPE_CPU, NULL);
        if (backend) {
            LOG_INFO("Initialized CPU backend from explicit preference");
        } else {
            LOG_WARN("CPU backend preference requested but CPU backend initialization failed");
        }
        return;
    }

    if (preferred_backend == SD_BACKEND_PREF_OPENCL) {
        const size_t n_devices = ggml_backend_dev_count();
        for (size_t i = 0; i < n_devices; ++i) {
            ggml_backend_dev_t dev = ggml_backend_dev_get(i);
            const enum ggml_backend_dev_type dev_type = ggml_backend_dev_type(dev);
            if (dev_type != GGML_BACKEND_DEVICE_TYPE_GPU &&
                dev_type != GGML_BACKEND_DEVICE_TYPE_IGPU) {
                continue;
            }
            const char* name = ggml_backend_dev_name(dev);
            if (!name) {
                continue;
            }
            const bool is_opencl = strstr(name, "opencl") != NULL ||
                                   strstr(name, "OpenCL") != NULL;
            if (!is_opencl) {
                continue;
            }
            backend = ggml_backend_dev_init(dev, NULL);
            if (backend) {
                LOG_INFO("Using OpenCL backend '%s'", name);
                LOG_INFO("Backend initialized successfully (OpenCL preference)");
                return;
            }
        }
        LOG_WARN("OpenCL preference requested but no OpenCL backend could be initialized; falling back to generic GPU selection");
    }

    backend = ggml_backend_init_by_type(GGML_BACKEND_DEVICE_TYPE_GPU, NULL);
    if (!backend) {
        LOG_WARN("GPU backend initialization failed; falling back to CPU backend");
        backend = ggml_backend_init_by_type(GGML_BACKEND_DEVICE_TYPE_CPU, NULL);
        if (!backend) {
            LOG_ERROR("CPU fallback backend initialization failed");
        }
    } else {
        LOG_INFO("Initialized generic GPU backend");
    }

    if (backend) {
        if (ggml_backend_is_cpu(backend)) {
            LOG_INFO("Final backend type: CPU");
        } else {
            LOG_INFO("Final backend type: non-CPU");
        }
    }
}

// Call site in StableDiffusionGGML::init(...)
// init_backend(sd_ctx_params->preferred_gpu_backend);

