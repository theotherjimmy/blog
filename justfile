render:
    env -C cuddly_kangaroo cargo build --release \
    && cuddly_kangaroo/target/release/cuddly_kangaroo blog.toml

serve: render
    miniserve -d monokai -- out

watch:
    fd | entr -nr -- just serve
    
