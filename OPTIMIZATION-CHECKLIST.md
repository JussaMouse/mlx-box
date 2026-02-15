# MLX-Box Optimization Checklist (128GB RAM)

## ✅ Implementation Status

### Configuration Updates

- [ ] **Router Service**
  - [ ] Increase max_tokens: 100 → 150
  - [x] Temperature: 0.1 (optimal for classification)
  - [x] Top-P: 0.9

- [ ] **Fast Service (Qwen3-30B-A3B-4bit)**
  - [ ] Increase max_tokens: 8192 → 16384
  - [x] Temperature: 0.6 (optimal)
  - [x] Top-P: 0.92 (optimal)
  - [ ] Optional: Enable disable_thinking_tags if model outputs thinking

- [ ] **Thinking Service (Qwen3-30B-A3B-Thinking-2507-4bit)**
  - [ ] Increase max_tokens: 16384 → 32768
  - [ ] Increase thinking_budget: 8192 → 16384
  - [ ] Adjust temperature: 0.2 → 0.6 (Qwen official recommendation)
  - [ ] Adjust top_p: 0.9 → 0.95 (better reasoning paths)
  - [ ] Enable disable_thinking_tags: true
  - [ ] Test if thinking tags are filtered (run test script)

- [ ] **Embedding Service (Qwen3-Embedding-8B)**
  - [ ] Increase batch_size: 64 → 128
  - [ ] Increase max_seq_length: 1024 → 2048
  - [x] Quantization: true (already enabled)

### Testing & Monitoring

- [ ] **Run benchmark script**
  ```bash
  ./scripts/benchmark-services.sh
  ```
  Expected results:
  - Router: 300-500 tok/s
  - Fast: 100-140 tok/s
  - Thinking: 50-80 tok/s
  - Embedding: ~200-400ms per query

- [ ] **Test thinking tags toggle**
  ```bash
  ./scripts/test-thinking-toggle.sh
  ```
  If tags still appear → implement streaming filter fallback

- [ ] **Monitor memory usage**
  ```bash
  ./scripts/monitor-memory.sh
  ```
  Target: 60-80GB used, 40-60GB headroom

- [ ] **Check service health**
  ```bash
  sudo launchctl list | grep -E "mlx-box|mlx"
  ```

### Performance Validation

After making changes:

- [ ] Restart all services:
  ```bash
  sudo launchctl kickstart -k system/com.mlx-box.router
  sudo launchctl kickstart -k system/com.mlx-box.fast
  sudo launchctl kickstart -k system/com.mlx-box.thinking
  sudo launchctl kickstart -k system/com.mlx-box.embedding
  ```

- [ ] Check logs for errors:
  ```bash
  tail -f ~/Library/Logs/com.mlx-box.fast/stderr.log
  tail -f ~/Library/Logs/com.mlx-box.thinking/stderr.log
  ```

- [ ] Verify no swap usage:
  ```bash
  sysctl vm.swapusage
  # Should show: used = 0.00M or very low
  ```

- [ ] Test a long context request (16K+ tokens)
- [ ] Test concurrent requests (5+ simultaneous)
- [ ] Monitor temperature and swap during load

## 📋 Configuration File Updates

### Current Settings (Before)
```toml
[services.router]
max_tokens = 100

[services.fast]
max_tokens = 8192
temperature = 0.6
top_p = 0.92

[services.thinking]
max_tokens = 16384
thinking_budget = 8192
temperature = 0.2
top_p = 0.9

[services.embedding]
batch_size = 64
max_seq_length = 1024
```

### Optimized Settings (After)
```toml
[services.router]
max_tokens = 150  # +50%

[services.fast]
max_tokens = 16384  # 2x increase
temperature = 0.6
top_p = 0.92

[services.thinking]
max_tokens = 32768       # 2x increase
thinking_budget = 16384  # 2x increase
temperature = 0.6        # Updated per Qwen recommendations
top_p = 0.95            # Updated per Qwen recommendations
disable_thinking_tags = true  # NEW: Filter thinking content

[services.embedding]
batch_size = 128         # 2x increase
max_seq_length = 2048    # 2x increase
```

## 🎯 Expected Improvements

### Context Capacity
- **Fast**: 8K → 16K tokens (2x longer conversations/documents)
- **Thinking**: 16K → 32K tokens (complex multi-step reasoning)
- **Embedding**: 1K → 2K tokens per chunk (better semantic capture)

### Throughput
- **Embedding**: 2x faster bulk processing (batch_size 128)
- **Router**: More detailed classification (+50% tokens)

### Quality
- **Thinking**: Better reasoning exploration (temp 0.6, top_p 0.95)
- **Thinking**: Cleaner output (thinking tags filtered)

### Memory Impact
With 128GB RAM and 60-70GB headroom:
- Can handle 8-12 concurrent long-context requests
- Fast 16K: ~4-6GB KV cache per request
- Thinking 32K: ~8-12GB KV cache per request
- Total capacity: ~7-8 concurrent thinking OR ~15 concurrent fast

## 🔧 Troubleshooting

### If memory pressure increases
1. Check swap: `sysctl vm.swapusage`
2. If swap > 1GB, reduce max_tokens or concurrent requests
3. Monitor: `./scripts/monitor-memory.sh`

### If thinking tags still appear
1. Run test: `./scripts/test-thinking-toggle.sh`
2. If failed, implement streaming filter fallback
3. Check mlx-lm version: `poetry show mlx-lm` (need >= 0.30.6)

### If performance degrades
1. Run benchmark: `./scripts/benchmark-services.sh`
2. Compare to baseline (Router 300+, Fast 100+, Thinking 50+)
3. Check logs for errors
4. Verify models loaded: `tail ~/Library/Logs/com.mlx-box.*/stderr.log`

## 📊 Success Criteria

All of these should be true after optimization:

- [x] All services responding to requests
- [ ] No swap usage (0.00M or < 100MB)
- [ ] Memory headroom > 30GB
- [ ] Router: 300+ tok/s
- [ ] Fast: 100+ tok/s
- [ ] Thinking: 50+ tok/s
- [ ] Thinking tags filtered (if enabled)
- [ ] Long context requests work (test 16K and 32K)
- [ ] Concurrent requests work (test 5+ simultaneous)

## 🚀 Next Steps (Future Optimizations)

1. **Implement streaming filter** for thinking tags (robust fallback)
2. **Add request queuing** to prevent memory spikes
3. **Set up automated monitoring** (cron job for memory checks)
4. **Create alert system** for memory pressure
5. **Optimize nginx** for better concurrent request handling
6. **Consider model caching** strategies for faster cold starts

## 📝 Notes

- **128GB RAM** is perfectly sized for this workload
- **60-70GB headroom** after loading all models
- **MoE architecture** (30B total, 3.3B active) keeps speed high
- **KV cache quantization** (8-bit) already enabled via patched server
- **All Qwen3 models** are latest generation (optimal choice)

---

**Last Updated**: 2025-02-15
**System**: Mac Studio M2 Ultra, 128GB RAM
**Models**: Qwen3-0.6B, Qwen3-30B-A3B (x2), Qwen3-Embedding-8B, olmOCR-2-7B
