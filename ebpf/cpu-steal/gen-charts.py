import matplotlib.pyplot as plt
import re
from datetime import datetime

# Load the log file
log_file = "vm-exit.log"

# Parse the log file
def parse_log(file_path):
    data = {}
    timestamps = []
    
    with open(file_path, "r") as file:
        current_time = None
        for line in file:
            # Match the timestamp line
            time_match = re.match(r"time: (.+)", line)
            if time_match:
                current_time = datetime.strptime(time_match.group(1), "%Y-%m-%d %H:%M:%S")
                timestamps.append(current_time)
                continue

            # Match data fields
            field_match = re.match(r"(\w+): \[(.+)\]", line)
            if field_match and current_time:
                field_name = field_match.group(1)
                values = list(map(int, field_match.group(2).split()))

                if field_name not in data:
                    data[field_name] = []

                data[field_name].append(values)

    return timestamps, data

def plot_fields(timestamps, data):
    for field, values_list in data.items():
        plt.figure(figsize=(12, 6))

        field_values = [sum(values) for values in values_list]  # Summing values for simplicity
        plt.plot(timestamps, field_values, label=field)

        plt.xlabel("Time")
        plt.ylabel("Value")
        plt.title(f"{field} Values Over Time")
        plt.legend()
        plt.grid(True)
        plt.xticks(rotation=45)
        plt.tight_layout()

        output_file = f"{field}_chart.png"
        plt.savefig(output_file)  # Save the chart to a file
        print(f"Chart for {field} saved to {output_file}")

# Main execution
def main():
    timestamps, data = parse_log(log_file)
    plot_fields(timestamps, data)

if __name__ == "__main__":
    main()

