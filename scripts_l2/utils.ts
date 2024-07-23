import fs from 'fs';
import dotenv from 'dotenv';

dotenv.config({ path: __dirname + '/../.env' })

export async function appendToEnv(name: string, address: string) {
    fs.appendFile(`${__dirname}/../.env`, `\n${name}_ADDRESS=${address}`, function (
        err,
    ) {
        if (err) throw err
    })
}