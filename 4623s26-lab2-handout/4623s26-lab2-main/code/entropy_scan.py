import sys, math
with open('csci4623-s26-lab2.dd','rb') as f:
    block = 0
    while True:
        data = f.read(4096)
        if not data: break
        if len(set(data)) <= 1:
            if block % 1000 == 0: print(f'Block {block}: zero/uniform')
        else:
            freq = [0]*256
            for b in data: freq[b] += 1
            ent = -sum((c/len(data))*math.log2(c/len(data)) for c in freq if c > 0)
            if block % 500 == 0 or ent < 3.0 or (ent > 7.9 and block % 100 == 0):
                print(f'Block {block} (offset 0x{block*4096:x}): entropy={ent:.3f}')
        block += 1
