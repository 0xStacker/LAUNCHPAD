import { StandardMerkleTree } from "@openzeppelin/merkle-tree";
import fs from "fs";

// Merkle tree of address(234), address(345) and address(456) for testing.
const values = [["0x00000000000000000000000000000000000000eA"],
                ["0x0000000000000000000000000000000000000159"],
                ["0x00000000000000000000000000000000000001c8"]
            ]

const merkleTree = StandardMerkleTree.of(values, ["address"]);
console.log("root", merkleTree.root);
fs.writeFileSync("merkleTree.json", JSON.stringify(merkleTree.dump()));
