#include <ggml.h>
#include <stable-diffusion.h>

#include <cstdio>
#include <cstring>
#include <string>

static_assert(GGML_MAX_NAME == 160, "Engine and consumer tensor layouts must agree");

int main() {
    sd_ctx_params_t params;
    sd_ctx_params_init(&params);
    params.tokenizer = "tokenizer.json";

    // Check the installed headers against the linked library's tensor layout.
    ggml_init_params init = {ggml_tensor_overhead(), nullptr, true};
    ggml_context* ctx = ggml_init(init);
    if (!ctx) return 1;
    ggml_tensor* tensor = ggml_new_tensor_1d(ctx, GGML_TYPE_F32, 1);
    const std::string name(144, 'n');
    ggml_set_name(tensor, name.c_str());
    const bool valid = tensor->ne[0] == 1 && tensor->type == GGML_TYPE_F32 &&
                       std::strcmp(ggml_get_name(tensor), name.c_str()) == 0;
    ggml_free(ctx);
    if (!valid) return 2;

    const char* info = sd_get_system_info();
    if (!info || !*info) return 3;
    std::puts(info);
    return 0;
}
