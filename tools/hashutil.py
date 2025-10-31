import hashlib,pathlib

def file_hash(path, algo="md5"):
    # calc file hash
    data=pathlib.Path(path).read_bytes()
    h=hashlib.new(algo)
    h.update(data)
    return h.hexdigest()
