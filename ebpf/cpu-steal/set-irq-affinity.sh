#!/bin/bash

# Read and modify smp_affinity for all IRQs under /proc/irq/
for irq_dir in /proc/irq/*/; do
    if [ -d "$irq_dir" ]; then
        irq=$(basename "$irq_dir")
        smp_affinity_file="${irq_dir}smp_affinity"
        
        if [ -f "$smp_affinity_file" ]; then
            affinity=$(cat "$smp_affinity_file" | tr -d '\n' | tr -d ' ')
            
            # Get the length of the hex string
            len=${#affinity}
            
            if [ $len -ge 4 ]; then
                # Extract last 16 bits (last 4 hex characters)
                last_16_bits="${affinity: -4}"
                
                # Check if last 16 bits are not zero
                if [ "$last_16_bits" != "0000" ]; then
                    # Set last 16 bits to zero while preserving the rest
                    new_affinity="${affinity%????}0000"
                    
                    # Write the new value back
                    echo "$new_affinity" > "$smp_affinity_file"
                    echo "IRQ $irq: $affinity -> $new_affinity (last 16 bits cleared)"
                else
                    echo "IRQ $irq: $affinity (no change needed)"
                fi
            else
                echo "IRQ $irq: $affinity (too short, skipping)"
            fi
        fi
    fi
done
