import sys
import mlx_lm
from mlx_lm import server

# Save original load
original_load = mlx_lm.load

# Monkey patch load to force kv_bits=8
def patched_load(*args, **kwargs):
    print("🚀 Loading model with KV Cache Quantization (8-bit)!")
    kwargs['kv_bits'] = 8
    return original_load(*args, **kwargs)

mlx_lm.load = patched_load

# Run the server's main function
if __name__ == '__main__':
    # Pass arguments to the server's argparser
    sys.argv = sys.argv # redundant but clear
    server.main()
