package main

import (
	"log"
	"os"
	"time"

	"github.com/cilium/ebpf/link"
	"github.com/cilium/ebpf/rlimit"
)

func main() {
	if err := rlimit.RemoveMemlock(); err != nil {
		log.Fatal(err)
	}

	objs := bpfObjects{}
	if err := loadBpfObjects(&objs, nil); err != nil {
		log.Fatalf("loading objects: %v", err)
	}
	defer objs.Close()

	kp, err := link.Tracepoint("kvm", "kvm_exit", objs.TpKvmExit, nil)
	if err != nil {
		log.Fatalf("opening tracepoint: %s", err)
	}
	defer kp.Close()

	logFile, err := os.OpenFile("vm-exit.log", os.O_RDWR|os.O_CREATE|os.O_APPEND, 0644)
	if err != nil {
		log.Fatalf("open vm-exit.log: %v", err)
	}
	defer logFile.Close()
	exitLog := log.New(logFile, "", 0)

	exitReason := map[uint32]string{0: "EXCEPTION_NMI", 1: "EXTERNAL_INTERRUPT", 2: "TRIPLE_FAULT", 3: "INIT_SIGNAL",
		7: "PENDING_INTERRUPT", 8: "NMI_WINDOW", 9: "TASK_SWITCH", 10: "CPUID",
		12: "HLT", 13: "INVD", 14: "INVLPG", 15: "RDPMC", 16: "RDTSC", 18: "VMCALL",
		19: "VMCLEAR", 20: "VMLAUNCH", 21: "VMPTRLD", 22: "VMPTRST", 23: "VMREAD",
		24: "VMRESUME", 25: "VMWRITE", 26: "VMOFF", 27: "VMON", 28: "CR_ACCESS",
		29: "DR_ACCESS", 30: "IO_INSTRUCTION", 31: "MSR_READ", 32: "MSR_WRITE",
		33: "INVALID_STATE", 34: "MSR_LOAD_FAIL", 36: "MWAIT_INSTRUCTION", 37: "MONITOR_TRAP_FLAG",
		39: "MONITOR_INSTRUCTION", 40: "PAUSE_INSTRUCTION", 41: "MCE_DURING_VMENTRY",
		43: "TPR_BELOW_THRESHOLD", 44: "APIC_ACCESS", 45: "EOI_INDUCED", 46: "GDTR_IDTR",
		47: "LDTR_TR", 48: "EPT_VIOLATION", 49: "EPT_MISCONFIG", 50: "INVEPT",
		51: "RDTSCP", 52: "PREEMPTION_TIMER", 53: "INVVPID", 54: "WBINVD", 55: "XSETBV",
		56: "APIC_WRITE", 57: "RDRAND", 58: "INVPCID", 59: "VMFUNC", 60: "ENCLS",
		61: "RDSEED", 62: "PML_FULL", 63: "XSAVES", 64: "XRSTORS", 67: "UMWAIT", 68: "TPAUSE"}

	log.Println("Start probing vm_exit and write statistics to vm-exit.log")
	log.Println("[ctrl+c to stop]")

	// Align time to 5 seconds
	now := time.Now().UnixMilli()
	timeAlign := 5000 - (now % 5000)
	time.Sleep(time.Duration(timeAlign) * time.Millisecond)

	var key uint32
	var diffValueAllCpu, prevValueAllCpu, currValueAllCpu [69][]uint64
	for {
		now = time.Now().UnixMilli()
		d := time.Unix(0, now*1000000)
		exitLog.Printf("time: %s", d.Format("2006-01-02 15:04:05"))

		for key = 0; key <= 68; key++ {
			if err := objs.CountingMap.Lookup(key, &currValueAllCpu[key]); err != nil {
				log.Fatalf("reading map: %v", err)
			}
			if len(prevValueAllCpu[key]) == 0 {
				prevValueAllCpu[key] = currValueAllCpu[key]
				diffValueAllCpu[key] = currValueAllCpu[key]
			}

			reason, keyExist := exitReason[key]
			for cpuid := 0; cpuid < len(currValueAllCpu[key]); cpuid++ {
				if keyExist {
					diffValueAllCpu[key][cpuid] = currValueAllCpu[key][cpuid] - prevValueAllCpu[key][cpuid]
				}
			}

			if keyExist {
				exitLog.Printf("%s: %v\n", reason, diffValueAllCpu[key])
			}
		}
		exitLog.Printf("\n")

		prevValueAllCpu = currValueAllCpu
		//log.Println(prevValueAllCpu)

		// wait until the next 5 second starts
		now = time.Now().UnixMilli()
		timeAlign = 5000 - (now % 5000)
		time.Sleep(time.Duration(timeAlign) * time.Millisecond)
	}
}
